import 'dart:io';
import 'dart:typed_data';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_editor_plus/image_editor_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'qr_code_screen.dart';
import '../services/firebase_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:open_file/open_file.dart';

class CameraScreen extends StatefulWidget {
  @override
  _CameraClassState createState() => _CameraClassState();
}

class _CameraClassState extends State<CameraScreen>  with WidgetsBindingObserver {
  // 画像を保持するためのFile型変数
  File? _image;
  // 画像が処理中か
  bool _isLoading = false;
  // カメラアクセス権の付与有無
  bool _permissionsGranted = false;
  // ストレージアクセス権の付与有無
  bool _storagePermissionsGranted= false;
  // ダイアログが開いているか
  bool _isDialogOpen = false;
  // 保存先（true=Storage, false=ローカル）
  bool _useFirebaseStorage = true;
  // ダイアログを表示するかどうか
  bool _showDialog = true;

  @override
  //ウィジェット初期化時にカメラアクセス権を確認
  void initState() {
    // 親クラス(State)のinitStateメソッドを呼び出す
    // ライフサイクルの変更を監視するためのオブザーバーを登録
    super.initState();
    _image = null;
    _checkRequiredAppInstallation();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  // ウィジェット破棄時にオブザーバを削除
  void dispose() {
    // ライフサイクルの変更を監視するためのオブザーバーを削除
    // メモリリーク対応
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  // アプリのライフサイクルが変更されたときに呼び出される。パーミッションと画像保持の初期化
  void didChangeAppLifecycleState(AppLifecycleState state) {

    // アプリがアクティブになったとき、前回表示していた画像をリセット
    if(state == AppLifecycleState.resumed) {
      setState(() {
        _image = null;
      });

      // アプリがアクティブになったとき、パーミッションのダイアログが開いていたら一度閉じる
      if(_isDialogOpen) {
        Navigator.of(context).pop();
        setState(() {
          // ダイアログフラグをfalseにセットしなおす。
          _isDialogOpen = false;
        });
      }
    }
  }

  Future<void> _checkRequiredAppInstallation() async {
    const requiredAppUrl = 'https://play.google.com/store/apps/details?id=com.dewmobile.kuaiya.play&hl=en';
    // 今後表示しない設定の確認
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool? isNeverShowAgain = prefs.getBool('never_show_dialog');
     if((isNeverShowAgain == null || !isNeverShowAgain) && _showDialog) {
       _showAppNotInstalledDialog(requiredAppUrl);
    }
  }

  void _showAppNotInstalledDialog(String url) {
    bool _isChecked = false;
    showDialog(
      context: context,
      builder:(BuildContext context)
    {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          return AlertDialog(
            title: Text('必要なアプリがインストールされていません'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                    'ローカルに保存したファイルを共有する場合は、ZAPYAをインストールする必要があります'),
                  Row(
                    children: [
                      Checkbox(
                        value: _isChecked,
                        onChanged: (bool? value) {
                          setState(() {
                            _isChecked = value!;
                          });
                        },
                      ),
                      Text('今後表示しない')
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    _launchUrl(url);
                    if (_isChecked) {
                      SharedPreferences prefs = await SharedPreferences
                        .getInstance();
                      await prefs.setBool('never_show_dialog', true);
                    }
                  },
                  child: Text('インストールする'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: Text('キャンセル'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _launchUrl(String url) async {
    if(await canLaunch(url)) {
      await launch(url);
    } else {
      throw 'Colud not launch $url';
    }
  }

  // カメラのパーミッションを確認し、状態に応じたダイアログを表示する
  Future<void> _checkCameraPermissions() async {
    // カメラのパーミッションをリクエスト
    var cameraRequest = await Permission.camera.request();
    print('カメラの権限:$cameraRequest');
    // パーミッションが許可された場合
    if(cameraRequest.isGranted) {
      setState((){
        _permissionsGranted = true;
      });
    //   権限が永久に拒否された場合
    } else if(cameraRequest.isPermanentlyDenied) {
      // アプリ側では再度権限リクエストができないためデバイスの設定画面を開く
      openAppSettings();
      //権限が一時的に拒否された場合
    } else if(cameraRequest.isDenied) {
      // 権限を再度要求するためのダイアログ
      _showCameraPermissionDialog();
      //権限が制限された場合
    } else if(cameraRequest.isLimited) {
      // フルアクセスを促すダイアログ
      _showCameraLimitedPermissionDialog();
    }
  }

  // ストレージのパーミッションを確認
  Future<void> _checkStoragePermission() async {
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    final int androidOsVersion = androidInfo.version.sdkInt;
    final iosInfo = await deviceInfo.iosInfo;
    final version = iosInfo.systemVersion;

    // Android端末の場合
    if(Platform.isAndroid) {
      print('androidのバージョン: $androidOsVersion');
      if (androidOsVersion >= 33) {
        // 現在の権限を確認
        var photoStatus = await Permission.photos.status;
        print('写真アクセスの権限: $photoStatus');
        if (photoStatus.isGranted) {
          setState(() {
            _storagePermissionsGranted = true;
          });
        } else {
          // フォト権限が付与されていなければユーザに許可を求める。
          var photoRequest = await Permission.photos.request();
          if (photoRequest.isPermanentlyDenied) {
            openAppSettings();
          } else if (photoRequest.isDenied) {
            _showStoragePermissionDialog();
          } else if (photoRequest.isLimited) {
            _showLimitedStoragePermissionDialog();
          }
        }
      } else {
        // Android13未満の場合
        // 現在の権限を確認
        var storageStatus = await Permission.storage.status;
        print('ストレージの権限: $storageStatus');
        if (storageStatus.isGranted) {
          setState(() {
            _storagePermissionsGranted = true;
          });
        } else {
          var storageRequest = await Permission.storage.request();
          if (storageRequest.isPermanentlyDenied) {
            openAppSettings();
          } else if (storageRequest.isDenied) {
            _showStoragePermissionDialog();
          } else if (storageRequest.isLimited) {
            _showLimitedStoragePermissionDialog();
          }
        }
      }
    }
  //   ios端末の場合
    if(Platform.isIOS) {
      if (int.parse(version.split('.')[0]) >= 14) {
        // iOS 14以上のケース
        var photoStatus = await Permission.photos.status;
        if (photoStatus.isGranted) {
          setState(() {
            _storagePermissionsGranted = true;
          });
        } else {
          var photoRequest = await Permission.photos.request();
          if (photoRequest.isPermanentlyDenied) {
            openAppSettings();
          } else if (photoRequest.isDenied) {
            _showStoragePermissionDialog();
          } else if (photoRequest.isLimited) {
            _showLimitedStoragePermissionDialog();
          }
        }
      } else {
        // iOS 14未満のケース
        var storageStatus = await Permission.storage.status;
        if (storageStatus.isGranted) {
          setState(() {
            _storagePermissionsGranted = true;
          });
        } else {
          var storageRequest = await Permission.storage.request();
          if (storageRequest.isPermanentlyDenied) {
            openAppSettings();
          } else if (storageRequest.isDenied) {
            _showStoragePermissionDialog();
          } else if (storageRequest.isLimited) {
            _showLimitedStoragePermissionDialog();
          }
        }
      }
    }
  }

  // 権限を再度要求するためのダイアログ
  void _showCameraPermissionDialog() {
    _isDialogOpen = true;
    showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('アプリ使用には権限の設定が必要です'),
            content: Text('このアプリを使用するために、カメラへのアクセス許可が必要です。設定画面に移動して権限を有効にしてください。'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _isDialogOpen = false;
                },
                child: Text('閉じる'),
              ),
              TextButton(
                  onPressed: () {
                    openAppSettings();
                  },
                  child: Text('設定に移動')
              ),
            ],
          );
        }
    );
  }

  // フルアクセスを許可するように促すダイアログ
  void _showCameraLimitedPermissionDialog() {
    _isDialogOpen = true;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('権限が制限されています'),
          content: Text('このアプリではカメラへのアクセスが制限されています。アプリを使用するために、カメラへのアクセスを許可してください。'),
          actions: [
            TextButton(
              onPressed:() {
                Navigator.of(context).pop();
                _isDialogOpen = false;
              },
              child: Text('閉じる'),
            ),
            TextButton(
              onPressed: () {
                openAppSettings();
                Navigator.of(context).pop();
              },
              child: Text('設定に移動'),
            ),
          ],
        );
      },
    );
  }

  void _showStoragePermissionDialog() {
    print("ダイアログを表示します");
    if (!mounted) return;
    _isDialogOpen = true;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('写真へのアクセス権限が必要です'),
          content: Text('このアプリを使用するためには、写真へのアクセスが必要です。設定画面に移動して権限を有効にしてください。'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _isDialogOpen = false;
                print("ダイアログが閉じられました");
              },
              child: Text('閉じる'),
            ),
            TextButton(
              onPressed: () {
                openAppSettings();
              },
              child: Text('設定に移動'),
            ),
          ],
        );
      },
    );
  }

  void _showLimitedStoragePermissionDialog() {
    _isDialogOpen = true;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('制限付きの写真アクセス'),
          content: Text('このアプリでは制限された写真アクセスが有効になっています。フルアクセスを許可してください。'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _isDialogOpen = false;
              },
              child: Text('閉じる'),
            ),
            TextButton(
              onPressed: () {
                openAppSettings();
              },
              child: Text('設定に移動'),
            ),
          ],
        );
      },
    );
  }

  // カメラを開く。
  Future<void> _openCamera() async{
    // カメラのパーミッションを有効にするダイアログを表示する
    if(!_permissionsGranted){
      await _checkCameraPermissions();
    }

    // パーミッションが付与されていない場合は戻る
    if (!_permissionsGranted) {
      return;
    }

    // ストレージのパーミッションを有効にするダイアログを表示する
    if(!_storagePermissionsGranted && !_useFirebaseStorage){
      await _checkStoragePermission();
    }

    // ストレージのパーミッションが付与されていない場合は戻る
    if (!_storagePermissionsGranted && !_useFirebaseStorage) {
      return;
    }

    // パーミッションが有効な場合はカメラを開き写真を撮影。
    // ImageSource.cameraでカメラを起動し、画像撮影を待つ。
    // pickedFileはユーザが撮影した画像ファイルを表すオブジェクト
    final XFile? pickedFile = await ImagePicker().pickImage(source: ImageSource.camera);
    if(pickedFile != null) {
      // 画像撮影をしたら、image変数に値を格納。
      // 画像編集画面に遷移する
      setState(() {
        _image = File(pickedFile.path);
      });
      _editImage(pickedFile.path);
    }
  }

  // 撮影した画像を編集するエディタを開く
  Future<void> _editImage(String imagePath) async {
    //画像パスからFileオブジェクトを作成
    final File imageFile = File(imagePath);

    // 画像編集画面に遷移
    final editedImage = await Navigator.push(
      context,
      // ImageEditorに編集対象の画像データを渡す
      MaterialPageRoute(
        builder: (context) => ImageEditor(
          image: imageFile.readAsBytesSync(),
        ),
      ),
    );

    // 編集後画像がnullでなければ保存処理を行う。
    if(editedImage != null) {
      print('Edited image received: $editedImage');
      // プログレスインジケータを表示するためにロード状態に変更する
      setState((){
        _isLoading = true;
      });
      // 編集後画像を、saveEditedImageに渡す
      _saveEditedImage(editedImage);
    } else {
      print('No edited image returned');
    }
  }

  Future<String> _saveImageToLocalStorage(Uint8List imageBytes) async {
    String filePath = '';
    if(Platform.isAndroid) {
      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final int androidOsVersion = androidInfo.version.sdkInt;

      if(androidOsVersion >= 33) {
        print('AndroidVer13以上');
        filePath = await _saveImageToExternalStorageAndroid13OrLater(imageBytes);
      } else {
        print('AndroidVer13未満の処理');
        filePath = await _saveImageToExternalStorageAndroidBelow13(imageBytes);
      }
    } else if(Platform.isIOS) {
      filePath = await _saveImageToLocalStorageIOS(imageBytes);
    }  else {
      throw Exception('未対応のプラットフォームです');
    }
    _image = null;
    await _openFileInGallery(filePath);
    return filePath;
  }

  Future<String> _saveImageToExternalStorageAndroid13OrLater(Uint8List imageBytes) async {
    final Directory directory = Directory('/storage/emulated/0/Pictures/testapp');
    String dirPath = directory.path;
    Directory newDirectory = Directory(dirPath);

    if(!await newDirectory.exists()) {
        await newDirectory.create(recursive: true);
    }

    final String filePath = '$dirPath/edited_image_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final file = File(filePath);
    await file.writeAsBytes(imageBytes);
    print('画像が保存されました； $filePath');
    return filePath;
  }

  Future<String> _saveImageToExternalStorageAndroidBelow13(Uint8List imageBytes) async{
    final Directory directory = Directory('/storage/emulated/0/Pictures/testapp');
    String dirPath = directory.path;
    Directory newDirectory = Directory(dirPath);

    if(!await newDirectory.exists()) {
      await newDirectory.create(recursive: true);
    }

    final String filePath = '$dirPath/edited_image_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final file = File(filePath);
    await file.writeAsBytes(imageBytes);
    print('画像が保存されました： $filePath');
    return filePath;
  }

  Future<String> _saveImageToLocalStorageIOS(Uint8List imageBytes) async {
    final result = await ImageGallerySaver.saveImage(
      imageBytes,
      quality: 100,
      name: 'edited_image_${DateTime.now().millisecondsSinceEpoch}'
    );
    if(result['isSuccess']) {
      print('画像がフォトライブラリに保存されました');
      return result['filePath'];
    } else {
      throw Exception('画像の保存に失敗しました');
    }
    // final directory = await getApplicationDocumentsDirectory();
    // final filePath = '${directory.path}/edited_image_${DateTime.now().millisecondsSinceEpoch}.jpg';
    // final file = File(filePath);
    //
    // await file.writeAsBytes(imageBytes);
    // print('画像がIOSのローカルに保尊されました $filePath');
    // return filePath;
  }

  Future<void> _openFileInGallery(String filePath) async {
    if(Platform.isAndroid || Platform.isIOS) {
      final result = await OpenFile.open(filePath);
      if (result.type == ResultType.error) {
        print('Error opening file: ${result.message}');
      }
    } else {
        throw '未対応のプラットフォームです';
    }
  }

  // 加工した画像を保存する。
  Future<void> _saveEditedImage(Uint8List editedImageData) async {
    try {
      String imageUrl;
      String localUrl;

      if(_useFirebaseStorage) {
        if(await _isOnline()) {
          // 一時ディレクトリに画像を保存する
          // getTemporaryDirectoryでデバイスの一時保存先のパスを取得
          final directory = await getTemporaryDirectory();
          // 一時保存先のパスに対してedited_image.jpgという名前で画像を保存
          final editedImagePath = '${directory.path}/edited_image.jpg';
          // 編集後の画像バイトデータを書き込み（editedImageFile）、画像ファイルとして保存する
          final File editedImageFile = File(editedImagePath);
          await editedImageFile.writeAsBytes(editedImageData);
          // 保存した画像をFirebaseStorageにアップロードする
          // 画像が正常にアップロードされた場合、imageUrlに格納先URLが格納される。
          imageUrl = await FirebaseService.uploadImage(editedImageFile);
          print('imageUrlの確認: $imageUrl');
          if (imageUrl.isNotEmpty) {
            print('Image uploaded successfully: $imageUrl');
            // pushを使ってQRコード表示画面へ遷移
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => QRCodeScreen(imageUrl: imageUrl),
              ),
            );
          } else {
            // アップロード処理に失敗した場合
            print('Failed to upload image');
          }
        } else {
          localUrl = await _saveImageToLocalStorage(editedImageData);
          // オフラインの場合はローカルに保存
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('現在オフラインです。ローカルに保存しました：$localUrl')),
          );
        }
      } else {
        // ローカルに保存
        localUrl = await _saveImageToLocalStorage(editedImageData);
        print('ローカルに保存した画像のパス: $localUrl');
      }
      // アップロードが正常終了した場合の処理
    } catch(e) {
      // ファイルの保存やアップデートに失敗した場合
      print('Error saving or uploading image: $e');
    } finally {
      // すべての処理が終わったらローディング状態を解除
      setState((){
        _isLoading = false;
      });
    }
  }

  // オフライン状態を確認する
  Future<bool> _isOnline() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    print('ネットワーク: $connectivityResult');
    if(connectivityResult is List<ConnectivityResult>) {
      print('接続状態のリスト: $connectivityResult');
      return connectivityResult.contains(ConnectivityResult.mobile)||
            connectivityResult.contains(ConnectivityResult.wifi);
    } else {
      if(connectivityResult == ConnectivityResult.mobile ||
          connectivityResult == ConnectivityResult.wifi) {
        // オンライン
        print('ネットワークオンライン');
        return true;
      }
    }
    // オフライン
    print('ネットワークオフライン');
    return false;
  }

  // 保存先選択画面
  void _showStorageSelectionDialog() {
   showDialog(
     context: context,
     builder: (BuildContext context) {
       return AlertDialog(
         title: Text('保存先を選択'),
         content: Column(
           mainAxisSize: MainAxisSize.min,
           children:[
             ListTile(
               title: Text('FirebaseStorageに保存'),
               leading: Radio(
                 value: true,
                 groupValue: _useFirebaseStorage,
                 onChanged: (bool? value) {
                   setState((){
                     _useFirebaseStorage = value!;
                   });
                   Navigator.of(context).pop();
                 },
               ),
             ),
             ListTile(
               title: Text('ローカルに保存'),
               leading: Radio(
                 value: false,
                 groupValue: _useFirebaseStorage,
                 onChanged: (bool? value) {
                   setState((){
                     _useFirebaseStorage = value!;
                   });
                   Navigator.of(context).pop();
                 },
               ),
             ),
           ],
         ),
         actions:[
           TextButton(
             onPressed:() {
               Navigator.of(context).pop();
             },
             child: Text('キャンセル'),
           ),
         ],
       );
     },
   );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // アプリ上部に表示されるタイトル
      appBar: AppBar(title: Text('Camera & Image Editor App')),
      // Centerウィジェットを使用して表示（画面中央に表示される）
      body: Center(
        child: _isLoading
            // ローディング中であれば、プログレスインジケータを表示
            ? CircularProgressIndicator()
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: _openCamera,
                    child: Text('カメラを開く'),
                  ),
                  SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: _showStorageSelectionDialog,
                    child: Text('保存先を選択'),
                  ),
                  Text(_useFirebaseStorage
                      ? '現在の保存先: Firebase Storage'
                      : '現在の保存先: ローカル'),
                  _image != null ? Image.file(_image!):Container(),
                ],
            ),
      ),
    );
  }
}
