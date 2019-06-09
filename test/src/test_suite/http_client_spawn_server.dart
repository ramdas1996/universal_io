// Copyright 'dart-universal_io' project authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:stream_channel/stream_channel.dart';

void hybridMain(StreamChannel channel, Object message) async {
  handleChannel(channel.cast<List>());
}

void handleChannel(StreamChannel channel) {
  final httpServerCompleter = Completer<HttpServer>();
  final doneCompleter = Completer();
  channel.stream.listen((message) async {
    final type = message[0] as String;
    switch (type) {
      case "bind":
        // Bind
        httpServerCompleter.complete(HttpServer.bind(
          "localhost",
          0,
        ));
        break;

      case "bindSecure":
        // Create TLS security context
        final securityContext = SecurityContext();
        securityContext.useCertificateChain(
          "test/src/test_suite/localhost.crt",
        );
        securityContext.usePrivateKey(
          "test/src/test_suite/localhost.key",
        );

        // Bind
        httpServerCompleter.complete(HttpServer.bindSecure(
          "localhost",
          0,
          securityContext,
        ));
        break;

      default:
        throw ArgumentError("Unsupported message type '$type'");
    }
  }, onDone: () {
    if (!httpServerCompleter.isCompleted) {
      httpServerCompleter.complete();
    }
    doneCompleter.complete();
  });

  // When we receive a server
  httpServerCompleter.future.then((server) {
    if (server == null) {
      return;
    }

    // Tell the test where we are listening
    channel.sink.add(["info", server.port]);

    // Close it when the channel closes
    doneCompleter.future.whenComplete(() {
      server.close();
    });

    // Listen for requests
    server.listen(
      (request) {
        handleHttpRequest(channel, request);
      },
      onError: (error, stackTrace) {
        channel.sink.addError(error, stackTrace);
      },
      onDone: () {
        channel.sink.close();
      },
    );
  });
}

void handleHttpRequest(StreamChannel channel, HttpRequest request) async {
  // Decode request body
  final requestBody = await utf8.decodeStream(request);

  // Tell the test about the request we received
  if (request.method != "OPTIONS") {
    channel.sink.add([
      "request",
      request.method,
      request.uri.toString(),
      requestBody,
    ]);
  }

  // Respond based on the path
  final response = request.response;

  // Check that the request is from loopback
  if (!request.connectionInfo.remoteAddress.isLoopback) {
    throw StateError("Unauthorized remote address");
  }

  // CORS:
  // We need to allow origin.
  final origin = request.headers.value("Origin");
  response.headers.set(
    "Access-Control-Allow-Origin",
    origin ?? "*",
  );

  // CORS:
  // We need allow methods that are not simple.
  // (simple methods are GET, HEAD, POST)
  response.headers.set(
    "Access-Control-Allow-Methods",
    "DELETE, GET, HEAD, PATCH, POST, PUT",
  );

  // CORS:
  // We need to allow reading our example response header.
  response.headers.set(
    "Access-Control-Expose-Headers",
    "X-Response-Header",
  );

  response.headers.set("X-Response-Header", "value");
  response.headers.contentType = ContentType.text;

  switch (request.uri.path) {
    case "/greeting":
      response.statusCode = 200;
      response.write("Hello world!");
      break;

    case "/allow_cors_credentials":
      response.statusCode = 200;
      response.headers.set("Access-Control-Allow-Credentials", "true");
      response.cookies.add(Cookie("exampleName", "exampleValue"));
      response.write("Hello world!");
      break;

    case "/404":
      response.statusCode = 404;
      break;

    default:
      response.statusCode = 500;
      response.write("Invalid path '${request.uri.path}'");
      break;
  }
  await request.response.close();
}