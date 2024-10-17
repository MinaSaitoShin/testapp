import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class QRCodeScreen extends StatelessWidget {
  final String imageUrl;

  QRCodeScreen({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    // ウィジェットの構成を定義
    return Scaffold(
      appBar: AppBar(title: Text('QR Code')),
      // 子ウィジェットを構成。画面中央に配置させている。
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // QRコードを生成して表示
            QrImageView(
              data: imageUrl,
              version: QrVersions.auto,
              size: 200.0,
            ),
            // メッセージ表示（QRコードを読み込むように指示）
            SizedBox(height: 30),
            Text('画像を表示するには、QRコードをスキャンしてください。'),
            // ボタンを作成
            ElevatedButton(
              onPressed:() {
                //カメラに戻る
                Navigator.pop(context);
              },
              child:Text('カメラに戻る'),
            ),
          ],
        ),
      ),
    );
  }
}