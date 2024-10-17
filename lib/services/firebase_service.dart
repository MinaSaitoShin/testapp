import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
//一時帝にコメントアウト（サーバの画像自動削除には必要）
// import 'package:cloud_firestore/cloud_firestore.dart';


class FirebaseService {
  // 受け取った画像をFirebaseStorageに格納する
  static Future<String> uploadImage(File image) async {
    // Storageに保存できたら格納先Urlを返す
    try {
      // 画像ファイル名の生成。現在の日時をミリ単位で取得しファイル名とすることで同一名のファイルが生成されるのを防ぐ
      String fileName = DateTime.now().millisecondsSinceEpoch.toString() + '.jpg';
      // FirebaseStorageのルートを参照
      Reference storageReference = FirebaseStorage.instance.ref().child('images/$fileName');
      // 指定した画像のアップロード
      UploadTask uploadTask = storageReference.putFile(image);
      // アップロード処理が完了するのを待つ。
      TaskSnapshot taskSnapshot = await uploadTask;
      // アップロードが完了したらtaskSnapshotからアップロードしたファイルのダウンロードURLを取得
      String downloadUrl = await taskSnapshot.ref.getDownloadURL();
      //一時帝にコメントアウト（サーバの画像自動削除には必要）
      // final uploadTime = DateTime.now();
      // await FirebaseFirestore.instance.collection('images').add({
      //   'url': downloadUrl,
      //   'uploadTime': uploadTime.toIso8601String(),
      // });
      return downloadUrl;
    } catch(e) {
      // アップロード処理に失敗した場合
      print('Error uploading image $e');
      return '';
    }
  }
}