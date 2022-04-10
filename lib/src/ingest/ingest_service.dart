/*
 * Copyright (c) TIKI Inc.
 * MIT license. See LICENSE file in root directory.
 */

import 'package:httpp/httpp.dart';
import 'package:logging/logging.dart';

import '../edge/edge_service.dart';
import 'ingest_model_req.dart';
import 'ingest_model_rsp.dart';
import 'ingest_repository.dart';

class IngestService {
  final _log = Logger('IngestService');
  final HttppClient _client;
  final EdgeService _edgeService;
  final IngestRepository _repository;
  final Future<void> Function(void Function(String?)? onSuccess)? refresh;

  IngestService({Httpp? httpp, this.refresh, required EdgeService edgeService})
      : _client = httpp == null ? Httpp().client() : httpp.client(),
        _edgeService = edgeService,
        _repository = IngestRepository();

  Future<void> write(
          {required IngestModelReq req,
          String? accessToken,
          Function(Object)? onError,
          Function()? onSuccess}) =>
      _refresh(accessToken, (err) {
        _log.severe(err);
        if (onError != null) onError(err);
      },
          (token, onError) => _repository.write(
              client: _client,
              accessToken: token,
              body: req,
              onSuccess: (retry) async {
                if (retry.retryIn != null)
                  await _edgeService.retryIn(req.fingerprint!, retry.retryIn!);
                else
                  await _edgeService
                      .pushed(req.fingerprint!); //TODO test this func.
              },
              onError: onError));

  Future<T> _refresh<T>(
      String? accessToken,
      Function(Object)? onError,
      Future<T> Function(String?, Future<void> Function(Object))
          request) async {
    return request(accessToken, (error) async {
      if (error is IngestModelRsp && error.code == 401 && refresh != null) {
        await refresh!((token) async {
          if (token != null)
            await request(
                token,
                (error) async =>
                    onError != null ? onError(error) : throw error);
        });
      } else
        onError != null ? onError(error) : throw error;
    });
  }
}
