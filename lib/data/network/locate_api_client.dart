import "package:dio/dio.dart";

class LocateApiResult {
  const LocateApiResult({
    required this.downloadUrl,
    required this.uploadUrl,
    this.serverInfo,
  });

  final String downloadUrl;
  final String uploadUrl;
  final String? serverInfo;
}

class LocateApiException implements Exception {
  const LocateApiException(this.message);

  final String message;

  @override
  String toString() => "LocateApiException: $message";
}

class LocateApiClient {
  LocateApiClient(this._dio);

  final Dio _dio;

  Future<LocateApiResult> nearest() async {
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        "https://locate.measurementlab.net/v2/nearest/ndt/ndt7",
        queryParameters: <String, dynamic>{
          "client_name": "flutter-ndt7-speedtest",
          "client_version": "1.0.0",
        },
      );
      final Object? payload = response.data;
      if (payload is! Map<String, dynamic>) {
        throw const LocateApiException("Invalid locate payload");
      }
      final List<dynamic>? results = payload["results"] as List<dynamic>?;
      if (results == null || results.isEmpty) {
        throw const LocateApiException("No nearby test server found");
      }

      for (final dynamic item in results) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final Map<String, dynamic>? urls =
            item["urls"] as Map<String, dynamic>?;
        final String? download = urls?["wss:///ndt/v7/download"] as String?;
        final String? upload = urls?["wss:///ndt/v7/upload"] as String?;
        if (download != null && upload != null) {
          final String machine = (item["machine"] as String?) ?? "";
          final Map<String, dynamic>? location =
              item["location"] as Map<String, dynamic>?;
          final String city = (location?["city"] as String?) ?? "";
          final String country = (location?["country"] as String?) ?? "";
          final String info = <String>[
            machine,
            city,
            country,
          ].where((String value) => value.trim().isNotEmpty).join(" / ");
          return LocateApiResult(
            downloadUrl: download,
            uploadUrl: upload,
            serverInfo: info.isEmpty ? null : info,
          );
        }
      }
      throw const LocateApiException("No valid NDT7 URLs in locate response");
    } on DioException catch (_) {
      throw const LocateApiException("Failed to retrieve nearest test server");
    }
  }
}
