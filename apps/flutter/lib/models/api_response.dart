import 'package:another_iptv_player/models/server_info.dart';
import 'package:another_iptv_player/models/user_info.dart';

class ApiResponse {
  final UserInfo userInfo;
  final ServerInfo serverInfo;
  final String playlistId;

  ApiResponse({
    required this.userInfo,
    required this.serverInfo,
    required this.playlistId,
  });

  factory ApiResponse.fromJson(Map<String, dynamic> json, String playlistId) {
    return ApiResponse(
      playlistId: playlistId,
      userInfo: UserInfo.fromJson(json['user_info'] ?? {}, playlistId),
      serverInfo: ServerInfo.fromJson(json['server_info'] ?? {}, playlistId),
    );
  }

  ApiResponse withPlaylistId(String newPlaylistId) {
    return ApiResponse(
      playlistId: newPlaylistId,
      userInfo: UserInfo(
        id: userInfo.id,
        playlistId: newPlaylistId,
        username: userInfo.username,
        password: userInfo.password,
        message: userInfo.message,
        auth: userInfo.auth,
        status: userInfo.status,
        expDate: userInfo.expDate,
        isTrial: userInfo.isTrial,
        activeCons: userInfo.activeCons,
        createdAt: userInfo.createdAt,
        maxConnections: userInfo.maxConnections,
        allowedOutputFormats: userInfo.allowedOutputFormats,
      ),
      serverInfo: ServerInfo(
        id: serverInfo.id,
        playlistId: newPlaylistId,
        url: serverInfo.url,
        port: serverInfo.port,
        httpsPort: serverInfo.httpsPort,
        serverProtocol: serverInfo.serverProtocol,
        rtmpPort: serverInfo.rtmpPort,
        timezone: serverInfo.timezone,
        timestampNow: serverInfo.timestampNow,
        timeNow: serverInfo.timeNow,
      ),
    );
  }
}
