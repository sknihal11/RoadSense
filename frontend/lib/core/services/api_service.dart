import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_constants.dart';

final apiServiceProvider = Provider<ApiService>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: AppConstants.baseApiUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));
  
  // Interceptors can be added here for authentication or logging
  dio.interceptors.add(LogInterceptor(
    requestHeader: true,
    requestBody: true,
    responseBody: true,
  ));
  
  return ApiService(dio);
});

class ApiService {
  final Dio _dio;

  ApiService(this._dio);

  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      final response = await _dio.get(
        path,
        queryParameters: queryParameters,
        options: options,
      );
      return response;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<Response> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      final response = await _dio.post(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
      return response;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<Response> postMultipartFormData(
    String path, {
    required Map<String, dynamic> data,
    Options? options,
  }) async {
    try {
      final formData = FormData.fromMap(data);
      final response = await _dio.post(
        path,
        data: formData,
        options: options,
      );
      return response;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Exception _handleDioError(DioException error) {
    String message = 'An unexpected error occurred';
    if (error.response != null) {
      message = 'Server error (${error.response?.statusCode}): ${error.response?.statusMessage}';
    } else {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
          message = 'Connection timeout';
          break;
        case DioExceptionType.sendTimeout:
          message = 'Send timeout';
          break;
        case DioExceptionType.receiveTimeout:
          message = 'Receive timeout';
          break;
        case DioExceptionType.cancel:
          message = 'Request cancelled';
          break;
        default:
          message = 'Network connection failed';
      }
    }
    return Exception(message);
  }
}
