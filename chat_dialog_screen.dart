import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:chatconnectycubesdk/api/model.dart' as prefix0;
import 'package:chatconnectycubesdk/api/model.dart';
import 'package:chatconnectycubesdk/api/persenter.dart';
import 'package:chatconnectycubesdk/utils/consts.dart';
import 'package:chatconnectycubesdk/utils/pref_util.dart';
import 'package:chatconnectycubesdk/widgets/common.dart';
import 'package:chatconnectycubesdk/widgets/full_photo.dart';
import 'package:chatconnectycubesdk/widgets/loading.dart';
import 'package:connectycube_sdk/connectycube_chat.dart';
import 'package:connectycube_sdk/connectycube_pushnotifications.dart';
import 'package:connectycube_sdk/connectycube_storage.dart';
import 'package:connectycube_sdk/src/chat/models/message_status_model.dart';
import 'package:connectycube_sdk/src/chat/models/typing_status_model.dart';
import 'package:device_info/device_info.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_apns/flutter_apns.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_details_screen.dart';

class ChatDialogScreen extends StatelessWidget {
  final CubeUser _cubeUser;
  CubeDialog _cubeDialog;

  ChatDialogScreen(this._cubeUser, this._cubeDialog);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ChatScreen(_cubeUser, _cubeDialog),
    );
  }
}

class ChatScreen extends StatefulWidget {
  static const String TAG = "_CreateChatScreenState";
  final CubeUser _cubeUser;
  final CubeDialog _cubeDialog;

  ChatScreen(this._cubeUser, this._cubeDialog);

  @override
  State createState() => ChatScreenState(_cubeUser, _cubeDialog);
}

class ChatScreenState extends State<ChatScreen> implements NotifiContract {
  final CubeUser _cubeUser;
  final CubeDialog _cubeDialog;

  final Map<int, CubeUser> _occupants = Map();

  File imageFile;
  File videoFile;
  final picker = ImagePicker();
  bool isLoading;
  String imageUrl;
  List<CubeMessage> listMessage;
  Timer typingTimer;
  bool isTyping = false;
  String userStatus = '';

  final TextEditingController textEditingController = TextEditingController();
  final ScrollController listScrollController = ScrollController();
  final FocusNode focusNode = FocusNode();
  final ChatMessagesManager chatMessagesManager =
      CubeChatConnection.instance.chatMessagesManager;

  final MessagesStatusesManager statusesManager =
      CubeChatConnection.instance.messagesStatusesManager;

  final TypingStatusesManager typingStatusesManager =
      CubeChatConnection.instance.typingStatusesManager;

  StreamSubscription<CubeMessage> msgSubscription;
  StreamSubscription<MessageStatus> deliveredSubscription;
  StreamSubscription<MessageStatus> readSubscription;
  StreamSubscription<TypingStatus> typingSubscription;

  final FirebaseMessaging firebaseMessaging = new FirebaseMessaging();
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      new FlutterLocalNotificationsPlugin();

  ChatScreenState(this._cubeUser, this._cubeDialog);

  @override
  void initState() {
    super.initState();
    focusNode.addListener(onFocusChange);
    msgSubscription =
        chatMessagesManager.chatMessagesStream.listen(onReceiveMessage);
    deliveredSubscription =
        statusesManager.deliveredStream.listen(onDeliveredMessage);
    readSubscription = statusesManager.readStream.listen(onReadMessage);
    typingSubscription =
        typingStatusesManager.isTypingStream.listen(onTypingMessage);

    isLoading = false;
    imageUrl = '';
    updateNotification();
    notificationEnable();
    getLastActivity();
    _getId();
    registerNotification();
    configLocalNotification();
//    sendPushNotification();
  }

  @override
  void dispose() {
    msgSubscription.cancel();
    deliveredSubscription.cancel();
    readSubscription.cancel();
    typingSubscription.cancel();
    textEditingController.dispose();
    super.dispose();
  }

  void updateNotification() {
    String dialogId = "${_cubeDialog.dialogId}";
    bool enable = true; // true - to enable, false - to disable

    updateDialogNotificationsSettings(dialogId, enable).then((isEnabled) {
      print('UPDATENOTIFICATIONSUCCESS ==> $isEnabled');
    }).catchError((error) {
      print('UPDATENOTIFICATIONERROR ==> $error');
    });
  }

  void notificationEnable() {
    String dialogId = _cubeDialog.dialogId;

    getDialogNotificationsSettings(dialogId).then((isEnabled) {
      print('NOTIFICATION ENABLE ==> $isEnabled');
    }).catchError((error) {
      print('NOTIFICATIONENABLE ERROR ==> $error');
    });
  }

  void registerNotification() async {
    firebaseMessaging.requestNotificationPermissions();

    firebaseMessaging.configure(onMessage: (Map<String, dynamic> message) {
      print('onMessage: $message');
//      showNotification(message['data']);
      return;
    }, onResume: (Map<String, dynamic> message) {
      print('onResume: $message');
      return;
    }, onLaunch: (Map<String, dynamic> message) {
      print('onLaunch: $message');
      return;
    });

    final connector = createPushConnector();

    connector.configure(
        onLaunch: onLaunch,
        onMessage: onMessage,
        onResume: onResume,
        onBackgroundMessage: onBackgroundMessage);

    connector.requestNotificationPermissions();

    if (connector.token.value != null) {
      String token = connector.token.value;
      print('Exist token: $token');
      subScription(token);
    } else {
      connector.token.addListener(() {
        String token = connector.token.value;
        print('Updated token: $token');
        subScription(token);
      });
    }

    SharedPreferences prefs = await SharedPreferences.getInstance();

    firebaseMessaging.requestNotificationPermissions(
//         IosNotificationSettings(sound: true, badge: true, alert: true)
        );

    firebaseMessaging.getToken().then((token) async {
      print('token: $token');
      prefs.setString('token', token);
    });
  }

  // Called when your app launched by PushNotifications
  Future<dynamic> onLaunch(Map<String, dynamic> data) {
    log('onLaunch, message: $data');
    return Future.value();
  }

// Called when your app become foreground from background by PushNotifications
  Future<dynamic> onResume(Map<String, dynamic> data) {
    log('onResume, message: $data');
    return Future.value();
  }

// Called when receive PushNotifications during your app is on foreground
  Future<dynamic> onMessage(Map<String, dynamic> data) async {
    log('onMessage, message: $data');
    showNotification();
    return Future.value();
  }

// Called when receive PushNotifications when app was stopped (Android only).
  static Future<dynamic> onBackgroundMessage(Map<String, dynamic> message) async {
    log('onBackgroundMessage,message: $message');
    if (message.containsKey('data')) {
      // Handle data message
      final dynamic data = message['data'];
//      message['data'] = message['notification'];
    }

    if (message.containsKey('notification')) {
      // Handle notification message
      final dynamic notification = message['notification'];
    }

    // Or do other work.
    return Future.value();
  }

  void configLocalNotification() {
    var initializationSettingsAndroid =
        new AndroidInitializationSettings('@mipmap/ic_launcher');
    var initializationSettingsIOS = new IOSInitializationSettings();
    var initializationSettings = new InitializationSettings(
        android: initializationSettingsAndroid, iOS: initializationSettingsIOS);
    flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  void showNotification() async {
    var androidPlatformChannelSpecifics = new AndroidNotificationDetails(
      Platform.isAndroid
          ? 'com.example.chatconnectycubesdk'
          : 'com.example.chatconnectycubesdk',
      'Flutter chat demo',
      'your channel description',
      playSound: true,
      enableVibration: true,
      importance: Importance.max,
      priority: Priority.high,
    );
    var iOSPlatformChannelSpecifics = new IOSNotificationDetails();
    var platformChannelSpecifics = new NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: iOSPlatformChannelSpecifics);
    await flutterLocalNotificationsPlugin.show(_cubeDialog.getRecipientId(),
        'Chat Notification', textEditingController.text, platformChannelSpecifics,
        payload: 'chat notification');
  }

  String dId = '';

  Future<String> _getId() async {
    var deviceInfo = DeviceInfoPlugin();
    if (Platform.isIOS) {
      // import 'dart:io'
      var iosDeviceInfo = await deviceInfo.iosInfo;
      setState(() {
        dId = iosDeviceInfo.identifierForVendor;
        print('IOS:::::::' + dId);
      });
      return iosDeviceInfo.identifierForVendor; // unique ID on iOS
    } else {
      var androidDeviceInfo = await deviceInfo.androidInfo;
      setState(() {
        dId = androidDeviceInfo.androidId;
        print('Android:::::::' + dId);
      });
      return androidDeviceInfo.androidId; // unique ID on Android
    }
  }

  Future<void> subScription(String token) async {
//    bool isProduction = bool.fromEnvironment('dart.vm.product');

    CreateSubscriptionParameters parameters = CreateSubscriptionParameters();
    parameters.environment = CubeEnvironment.DEVELOPMENT;
//    isProduction ? CubeEnvironment.PRODUCTION : CubeEnvironment.DEVELOPMENT;

    if (Platform.isAndroid) {
      parameters.channel = NotificationsChannels.GCM;
      parameters.platform = CubePlatform.ANDROID;
    } else if (Platform.isIOS) {
      parameters.channel = NotificationsChannels.APNS;
      parameters.platform = CubePlatform.IOS;
    }

    String deviceId = dId;
//        "2b6f0cc904d137be2e1730235f5664094b831186"; // some device identifier "2b6f0cc904d137be2e1730235f5664094b831186"
    parameters.udid = deviceId;
    print('pushToken====== $deviceId'); /*$token*/
    parameters.pushToken = '$deviceId';
    print('pushToken2====== $deviceId');
//      fcmToken;
//     "2b6f0cc9...4b831186";
//      token;

    parameters.bundleIdentifier =
        "com.example.chatconnectycubesdk"; // not required, a unique identifier for client's application. In iOS, this is the Bundle Identifier. In Android - package id

    createSubscription(parameters.getRequestParameters())
        .then((cubeSubscription) {
      print('SUBSCRIPTION SUCCESS ====> $cubeSubscription');
    }).catchError((error) {
      print('SUBSCRIPTION ERROR ==> $error');
    });
  }

  void sendPushNotification() {
//    bool isProduction = bool.fromEnvironment('dart.vm.product');
    CreateEventParams params = CreateEventParams();
    params.name = 'Notification Demo';
//    params.eventType = PushEventType.ONE_SHOT;

    params.parameters = {
      'message': '${textEditingController.text}',
      // 'message' field is required "Some message in push"
      'title': 'Chat Notification',
      'body': "chat body",
      'notification_type': 'push',
      'push_type': 'gcm',
      'environment': 'development',
      'ios_voip': 1,
      'usersIds': _cubeDialog.occupantsIds,
      'click_action': 'FLUTTER_NOTIFICATION_CLICK'
      // to send VoIP push notification to iOS
      //more standard parameters you can found by link https://developers.connectycube.com/server/push_notifications?id=universal-push-notifications
    };
    print('NOTIFICATION TYPE ====> ${NotificationType.PUSH}');
    params.notificationType = '${NotificationType.PUSH}';

    params.environment = CubeEnvironment.DEVELOPMENT;
    params.usersIds = _cubeDialog.occupantsIds;

    print('USERID =====> ${_cubeDialog.occupantsIds}');

    createEvent(params.getEventForRequest()).then((cubeEvent) async {
      print('CUBE EVENT -----> $cubeEvent');

    }).catchError((error) {
      print('CUBE EVENT ERROR -----> $error');
    });
  }

  void unsubscribe() {
    getSubscriptions()
        .then((subscriptionsList) {
          int subscriptionIdToDelete =
              subscriptionsList[0].id; // or other subscription's id
          return deleteSubscription(subscriptionIdToDelete);
        })
        .then((voidResult) {})
        .catchError((error) {});
  }

  void onFocusChange() {
    if (focusNode.hasFocus) {}
  }

  void openFile() async {
    FilePickerResult result = await FilePicker.platform.pickFiles();
    if (result != null) {
      File file = File(result.files.single.path);
      setState(() {
        isLoading = true;
      });
      imageFile = File(file.path);
    } else {
      // User canceled the picker
    }
    uploadImageFile();
  }

  void openGallery() async {
    final pickedFile = await picker.getImage(source: ImageSource.gallery);
    if (pickedFile == null) return;
    setState(() {
      isLoading = true;
    });
    imageFile = File(pickedFile.path);
    uploadImageFile();
  }

  void openVideo() async {
    final pickedFile = await picker.getVideo(source: ImageSource.gallery);
    if (pickedFile == null) return;
    setState(() {
      isLoading = true;
    });
    videoFile = File(pickedFile.path);
    uploadVideoFile();
  }

  String uid;

  Future uploadImageFile() async {
    uploadFile(imageFile, true).then((cubeFile) {
      var url = cubeFile.getPublicUrl();
      onSendChatAttachment(url);
    }).catchError((ex) {
      setState(() {
        isLoading = false;
      });
      Fluttertoast.showToast(msg: 'This file is not an image');
    });
  }

  Future uploadVideoFile() async {
    uploadFile(videoFile, true).then((cubeFile) {
      var url = cubeFile.getPublicUrl();
      onSendChatVideoAttachment(url);
    }).catchError((ex) {
      setState(() {
        isLoading = false;
      });
    });
  }

  _chatDetails(BuildContext context) async {
    log("_chatDetails= $_cubeDialog");
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatDetailsScreen(_cubeUser, _cubeDialog),
      ),
    );
  }

  void onReceiveMessage(CubeMessage message) {
    log("onReceiveMessage message= $message");
    if (message.dialogId != _cubeDialog.dialogId ||
        message.senderId == _cubeUser.id) return;
    _cubeDialog.readMessage(message);
    addMessageToListView(message);
  }

  void onDeliveredMessage(MessageStatus status) {
    log("onDeliveredMessage message= $status");
    updateReadDeliveredStatusMessage(status, false);
  }

  void onReadMessage(MessageStatus status) {
    log("onReadMessage message= ${status.messageId}");
    updateReadDeliveredStatusMessage(status, true);
  }

  void onTypingMessage(TypingStatus status) {
    log("TypingStatus message= ${status.userId}");
    if (status.userId == _cubeUser.id ||
        (status.dialogId != null && status.dialogId != _cubeDialog.dialogId))
      return;
    userStatus = _occupants[status.userId]?.fullName ??
        _occupants[status.userId]?.login ??
        '';
    if (userStatus.isEmpty) return;
    if (_cubeDialog.type == CubeDialogType.PRIVATE) {
      userStatus = "typing..."; /*$userStatus is */
    } else if (_cubeDialog.type == CubeDialogType.GROUP) {
      userStatus = '$userStatus is typing...';
    }

    if (isTyping != true) {
      setState(() {
        isTyping = true;
      });
    }
    startTypingTimer();
  }

  startTypingTimer() {
    typingTimer?.cancel();
    typingTimer = Timer(Duration(milliseconds: 900), () {
      setState(() {
        isTyping = false;
      });
    });
  }

//  NotifiPresenter _notifiPresenter;
//  NotificationModel notificationModel;

  void onSendChatMessage(String content) {
//    print("Jaimin " + document["pushToken"]);

//    NotificationModel item = NotificationModel();
////    item.to = snapshot.data.documents[0]['pushToken'].toString();
//
//    item.priority = "high";
//    prefix0.Notification n = prefix0.Notification();
//    n.title = "chat Notification";
//    n.body = textEditingController.text.toString();
//    item.notification = n;
//    _notifiPresenter.doNotification(item);
    if (content.trim() != '') {
      final message = createCubeMsg();
      message.body = content.trim();
      sendPushNotification();
      onSendMessage(message);
    } else {
      Fluttertoast.showToast(msg: 'Nothing to send');
    }
  }

  void onSendChatAttachment(String url) async {
    var decodedImage = await decodeImageFromList(imageFile.readAsBytesSync());

    final attachment = CubeAttachment();
    attachment.id = imageFile.hashCode.toString();
    attachment.type = CubeAttachmentType.IMAGE_TYPE;
    attachment.url = url;
    attachment.height = decodedImage.height;
    attachment.width = decodedImage.width;
    final message = createCubeMsg();
    message.body = "Attachment";
    message.attachments = [attachment];
    onSendMessage(message);
  }

  void onSendChatVideoAttachment(String url) async {
    print('id ======>>>> ${videoFile.hashCode.toString()}');
    final attachment = CubeAttachment();
    attachment.id = videoFile.hashCode.toString();
    attachment.type = CubeAttachmentType.VIDEO_TYPE;
    attachment.url = url;
    attachment.height = 200;
    attachment.height = 200;
    attachment.width = 200;
    final message = createCubeMsg();
    message.body = 'Attachment';
    message.attachments = [attachment];
    onSendMessage(message);
  }

  CubeMessage msg;

  CubeMessage createCubeMsg() {
    var message = CubeMessage();
    message.dateSent = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    message.markable = true;
    message.saveToHistory = true;
    return message;
  }

  void deleteMessage() {
    var message = CubeMessage();
    print('MESSAGEID => [${message.id.toString()}, ${message.messageId}]');
    List<String> ids = [message.id.toString(), message.messageId];
    bool force =
        false; // true - to delete everywhere, false - to delete for himself

    deleteMessages(ids, force).then((deleteItemsResult) {
      print('DELETEMESSAGESUCCESS ==> $deleteItemsResult');
    }).catchError((error) {
      print('DELETEMESSAGEERROR ==> $error');
    });
  }

  void onSendMessage(CubeMessage message) async {
    setState(() {
      msg = message;
    });
    log("onSendMessage message= $message");

    textEditingController.clear();
    await _cubeDialog.sendMessage(message);
    message.senderId = _cubeUser.id;
    addMessageToListView(message);
    listScrollController.animateTo(0.0,
        duration: Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  updateReadDeliveredStatusMessage(MessageStatus status, bool isRead) {
    CubeMessage msg = listMessage.firstWhere(
        (msg) => msg.messageId == status.messageId,
        orElse: () => null);
    if (msg == null) return;
    if (isRead)
      msg.readIds == null
          ? msg.readIds = [status.userId]
          : msg.readIds?.add(status.userId);
    else
      msg.deliveredIds == null
          ? msg.deliveredIds = [status.userId]
          : msg.deliveredIds?.add(status.userId);
    setState(() {});
  }

  addMessageToListView(message) {
    setState(() {
      isLoading = false;
      listMessage.insert(0, message);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: WillPopScope(
        child: Scaffold(
          appBar: AppBar(
            title: Padding(
              padding: EdgeInsets.only(top: 5, bottom: 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Text(
                    _cubeDialog.name != null ? _cubeDialog.name : '',
                    style: TextStyle(fontSize: 15, color: Colors.white),
                  ),
                  buildTyping(),
                ],
              ),
            ),
            centerTitle: false,
            actions: <Widget>[
              Text(lastActivity != null ? lastActivity : null),
              IconButton(
                onPressed: () => _chatDetails(context),
                icon: Icon(
                  Icons.info_outline,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          body: Stack(
            children: <Widget>[
              Column(
                children: <Widget>[
                  // List of messages
                  buildListMessage(),
                  //Typing content

                  // Input content
                  buildInput(),
                ],
              ),

              // Loading
              buildLoading()
            ],
          ),
        ),
        onWillPop: onBackPress,
      ),
    );
  }

  Widget buildItem(int index, CubeMessage message) {
    markAsReadIfNeed() {
      var isOpponentMsgRead =
          message.readIds != null && message.readIds.contains(_cubeUser.id);
      print(
          "markAsReadIfNeed message= ${message}, isOpponentMsgRead= $isOpponentMsgRead");
      if (message.senderId != _cubeUser.id && !isOpponentMsgRead) {
        if (message.readIds == null)
          message.readIds = [_cubeUser.id];
        else
          message.readIds.add(_cubeUser.id);
        _cubeDialog.readMessage(message);
      }
    }

    Widget getReadDeliveredWidget() {
      bool messageIsRead() {
        if (_cubeDialog.type == CubeDialogType.PRIVATE)
          return message.readIds != null &&
              (message.recipientId == null ||
                  message.readIds.contains(message.recipientId));
        return message.readIds != null &&
            message.readIds.any((int id) => _occupants.keys.contains(id));
      }

      bool messageIsDelivered() {
        if (_cubeDialog.type == CubeDialogType.PRIVATE)
          return message.deliveredIds?.contains(message.recipientId) ?? false;
        return message.deliveredIds != null &&
            message.deliveredIds.any((int id) => _occupants.keys.contains(id));
      }

      if (messageIsRead())
        return Stack(children: <Widget>[
          Icon(
            Icons.check,
            size: 15.0,
            color: blueColor,
          ),
          Padding(
            padding: EdgeInsets.only(left: 8),
            child: Icon(
              Icons.check,
              size: 15.0,
              color: blueColor,
            ),
          )
        ]);
      else if (messageIsDelivered()) {
        return Stack(children: <Widget>[
          Icon(
            Icons.check,
            size: 15.0,
            color: greyColor,
          ),
          Padding(
            padding: EdgeInsets.only(left: 8),
            child: Icon(
              Icons.check,
              size: 15.0,
              color: greyColor,
            ),
          )
        ]);
      } else {
        return Icon(
          Icons.check,
          size: 15.0,
          color: greyColor,
        );
      }
    }

    Widget getDateWidget() {
      return Text(
        DateFormat('HH:mm').format(
            DateTime.fromMillisecondsSinceEpoch(message.dateSent * 1000)),
        style: TextStyle(
            color: greyColor, fontSize: 12.0, fontStyle: FontStyle.italic),
      );
    }

    Widget getHeaderDateWidget() {
      return Container(
        alignment: Alignment.center,
        child: Text(
          DateFormat('dd MMMM').format(
              DateTime.fromMillisecondsSinceEpoch(message.dateSent * 1000)),
          style: TextStyle(
              color: primaryColor, fontSize: 20.0, fontStyle: FontStyle.italic),
        ),
        margin: EdgeInsets.all(10.0),
      );
    }

    bool isHeaderView() {
      int headerId = int.parse(DateFormat('ddMMyyyy').format(
          DateTime.fromMillisecondsSinceEpoch(message.dateSent * 1000)));
      if (index >= listMessage.length - 1) {
        return false;
      }
      var msgPrev = listMessage[index + 1];
      int nextItemHeaderId = int.parse(DateFormat('ddMMyyyy').format(
          DateTime.fromMillisecondsSinceEpoch(msgPrev.dateSent * 1000)));
      var result = headerId != nextItemHeaderId;
      return result;
    }

    if (message.senderId == _cubeUser.id) {
      // Right (own message)
      return Column(
        children: <Widget>[
          isHeaderView() ? getHeaderDateWidget() : SizedBox.shrink(),
          Row(
            children: <Widget>[
              message.attachments?.isNotEmpty ?? false
                  // Image
                  ? Container(
                      child: FlatButton(
                        child: Material(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                CachedNetworkImage(
                                  placeholder: (context, url) => Container(
                                    child: CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          themeColor),
                                    ),
                                    width: 200.0,
                                    height: 200.0,
                                    padding: EdgeInsets.all(70.0),
                                    decoration: BoxDecoration(
                                      color: greyColor2,
                                      borderRadius: BorderRadius.all(
                                        Radius.circular(8.0),
                                      ),
                                    ),
                                  ),
                                  errorWidget: (context, url, error) =>
                                      Material(
                                    child: Image.asset(
                                      'assets/images/splash.png',
                                      width: 200.0,
                                      height: 200.0,
                                      fit: BoxFit.cover,
                                    ),
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(8.0),
                                    ),
                                    clipBehavior: Clip.hardEdge,
                                  ),
                                  imageUrl: message.attachments.first.url,
                                  width: 200.0,
                                  height: 200.0,
                                  fit: BoxFit.cover,
                                ),
                                getDateWidget(),
                                getReadDeliveredWidget(),
                              ]),
                          borderRadius: BorderRadius.all(Radius.circular(8.0)),
                          clipBehavior: Clip.hardEdge,
                        ),
                        onPressed: () {
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => FullPhoto(
                                      url: message.attachments.first.url)));
                        },
                        padding: EdgeInsets.all(0),
                      ),
                      margin: EdgeInsets.only(
                          bottom: isLastMessageRight(index) ? 20.0 : 10.0,
                          right: 10.0),
                    )
                  : message.body != null && message.body.isNotEmpty
                      // Text
                      ? Flexible(
                          child: Container(
                            padding:
                                EdgeInsets.fromLTRB(15.0, 10.0, 15.0, 10.0),
                            decoration: BoxDecoration(
                                color: greyColor2,
                                borderRadius: BorderRadius.circular(8.0)),
                            margin: EdgeInsets.only(
                                bottom: isLastMessageRight(index) ? 20.0 : 10.0,
                                right: 10.0),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    message.body,
                                    style: TextStyle(color: primaryColor),
                                  ),
                                  getDateWidget(),
                                  getReadDeliveredWidget(),
                                ]),
                          ),
                        )
                      : Container(
                          child: Text(
                            "Empty",
                            style: TextStyle(color: primaryColor),
                          ),
                          padding: EdgeInsets.fromLTRB(15.0, 10.0, 15.0, 10.0),
                          width: 200.0,
                          decoration: BoxDecoration(
                              color: greyColor2,
                              borderRadius: BorderRadius.circular(8.0)),
                          margin: EdgeInsets.only(
                              bottom: isLastMessageRight(index) ? 20.0 : 10.0,
                              right: 10.0),
                        ),
            ],
            mainAxisAlignment: MainAxisAlignment.end,
          ),
        ],
      );
    } else {
      // Left (opponent message)
      markAsReadIfNeed();
      return Container(
        child: Column(
          children: <Widget>[
            isHeaderView() ? getHeaderDateWidget() : SizedBox.shrink(),
            Row(
              children: <Widget>[
                Material(
                  child: CircleAvatar(
                    backgroundImage:
                        _occupants[message.senderId].avatar != null &&
                                _occupants[message.senderId].avatar.isNotEmpty
                            ? NetworkImage(_occupants[message.senderId].avatar)
                            : null,
                    backgroundColor: greyColor2,
                    radius: 30,
                    child: getAvatarTextWidget(
                      _occupants[message.senderId].avatar != null &&
                          _occupants[message.senderId].avatar.isNotEmpty,
                      _occupants[message.senderId]
                          .fullName
                          .substring(0, 2)
                          .toUpperCase(),
                    ),
                  ),
                  borderRadius: BorderRadius.all(
                    Radius.circular(18.0),
                  ),
                  clipBehavior: Clip.hardEdge,
                ),
                message.attachments?.isNotEmpty ?? false
                    ? Container(
                        child: FlatButton(
                          child: Material(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CachedNetworkImage(
                                    placeholder: (context, url) => Container(
                                      child: CircularProgressIndicator(
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                themeColor),
                                      ),
                                      width: 200.0,
                                      height: 200.0,
                                      padding: EdgeInsets.all(70.0),
                                      decoration: BoxDecoration(
                                        color: greyColor2,
                                        borderRadius: BorderRadius.all(
                                          Radius.circular(8.0),
                                        ),
                                      ),
                                    ),
                                    errorWidget: (context, url, error) =>
                                        Material(
                                      child: Image.asset(
                                        'assets/images/splash.png',
                                        width: 200.0,
                                        height: 200.0,
                                        fit: BoxFit.cover,
                                      ),
                                      borderRadius: BorderRadius.all(
                                        Radius.circular(8.0),
                                      ),
                                      clipBehavior: Clip.hardEdge,
                                    ),
                                    imageUrl: message.attachments.first.url,
                                    width: 200.0,
                                    height: 200.0,
                                    fit: BoxFit.cover,
                                  ),
                                  getDateWidget(),
                                ]),
                            borderRadius:
                                BorderRadius.all(Radius.circular(8.0)),
                            clipBehavior: Clip.hardEdge,
                          ),
                          onPressed: () {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) => FullPhoto(
                                        url: message.attachments.first.url)));
                          },
                          padding: EdgeInsets.all(0),
                        ),
                        margin: EdgeInsets.only(left: 10.0),
                      )
                    : message.body != null && message.body.isNotEmpty
                        ? Flexible(
                            child: Container(
                              padding:
                                  EdgeInsets.fromLTRB(15.0, 10.0, 15.0, 10.0),
                              decoration: BoxDecoration(
                                  color: primaryColor,
                                  borderRadius: BorderRadius.circular(8.0)),
                              margin: EdgeInsets.only(left: 10.0),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      message.body,
                                      style: TextStyle(color: Colors.white),
                                    ),
                                    getDateWidget(),
                                  ]),
                            ),
                          )
                        : Container(
                            child: Text(
                              "Empty",
                              style: TextStyle(color: primaryColor),
                            ),
                            padding:
                                EdgeInsets.fromLTRB(15.0, 10.0, 15.0, 10.0),
                            width: 200.0,
                            decoration: BoxDecoration(
                                color: greyColor2,
                                borderRadius: BorderRadius.circular(8.0)),
                            margin: EdgeInsets.only(
                                bottom: isLastMessageRight(index) ? 20.0 : 10.0,
                                right: 10.0),
                          ),
              ],
            ),
          ],
          crossAxisAlignment: CrossAxisAlignment.start,
        ),
        margin: EdgeInsets.only(bottom: 10.0),
      );
    }
  }

  bool isLastMessageLeft(int index) {
    if ((index > 0 &&
            listMessage != null &&
            listMessage[index - 1].id == _cubeUser.id) ||
        index == 0) {
      return true;
    } else {
      return false;
    }
  }

  bool isLastMessageRight(int index) {
    if ((index > 0 &&
            listMessage != null &&
            listMessage[index - 1].id != _cubeUser.id) ||
        index == 0) {
      return true;
    } else {
      return false;
    }
  }

  Widget buildLoading() {
    return Positioned(
      child: isLoading ? const Loading() : Container(),
    );
  }

  Widget buildTyping() {
    return Visibility(
      visible: isTyping,
      child: Text(
        userStatus,
        style: TextStyle(color: Colors.white, fontSize: 10),
      ),
    );
  }

  void _attachmentBottomSheeet(context) {
    showModalBottomSheet(
        context: context,
        builder: (BuildContext bc) {
          return Container(
            child: Wrap(
              children: [
                ListTile(
                  leading: Icon(Icons.image),
                  title: Text('Images'),
                  onTap: () {
                    Navigator.pop(context);
                    openGallery();
                  },
                ),
                ListTile(
                  leading: Icon(Icons.video_collection),
                  title: Text('Video'),
                  onTap: () {
                    Navigator.pop(context);
                    openVideo();
                  },
                ),
//                ListTile(
//                  leading: Icon(Icons.music_note),
//                  title: Text('Audio'),
//                  onTap: () {
//                    Navigator.pop(context);
//                  },
//                ),
//                ListTile(
//                  leading: Icon(Icons.attach_file),
//                  title: Text('File'),
//                  onTap: () {
//                    Navigator.pop(context);
//                    openFile();
//                  },
//                )
              ],
            ),
          );
        });
  }

  Widget buildInput() {
    return Container(
      child: Row(
        children: <Widget>[
          // Button send image
          Material(
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: 1.0),
              child: IconButton(
                icon: Icon(Icons.image),
                onPressed: () {
//                  openGallery();
                  _attachmentBottomSheeet(context);
                },
                color: primaryColor,
              ),
            ),
            color: Colors.white,
          ),

          // Edit text
          Flexible(
            child: Container(
              child: TextField(
                style: TextStyle(color: primaryColor, fontSize: 15.0),
                controller: textEditingController,
                decoration: InputDecoration.collapsed(
                  hintText: 'Type your message...',
                  hintStyle: TextStyle(color: greyColor),
                ),
                focusNode: focusNode,
                onChanged: (text) {
                  _cubeDialog.sendIsTypingStatus();
                },
              ),
            ),
          ),

          // Button send message
          Material(
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: 8.0),
              child: IconButton(
                icon: Icon(Icons.send),
                onPressed: () => onSendChatMessage(textEditingController.text),
                color: primaryColor,
              ),
            ),
            color: Colors.white,
          ),
        ],
      ),
      width: double.infinity,
      height: 50.0,
      decoration: BoxDecoration(
          border: Border(top: BorderSide(color: greyColor2, width: 0.5)),
          color: Colors.white),
    );
  }

  String lastActivity = '';

  void getLastActivity() {
    int userId = _cubeDialog.getRecipientId();

    CubeChatConnection.instance.getLasUserActivity(userId).then((minutes) {
      // 'userId' was 'seconds' ago
      print('GET LAST ACTIVITY ==> $minutes');
      if (minutes.toString().length == 4) {
        setState(() {
          lastActivity =
              'Last Seen: ${minutes.toString().substring(0, 2)} minutes ago';
          print('Last Activity IF ==> $lastActivity');
        });
      } else if (minutes.toString().length == 5) {
        setState(() {
          lastActivity =
              'Last Seen: ${minutes.toString().substring(0, 3)} minutes ago';
          print('Last Activity ELSE ==> $lastActivity');
        });
      } else {
        setState(() {
          lastActivity =
              'Last Seen: ${minutes.toString().substring(0, 4)} minutes ago';
          print('Last Activity ELSE ==> $lastActivity');
        });
      }
    }).catchError((error) {
      // 'userId' never logged to the chat
      print('GET LAST ACTIVITY ERROR ==> $error');
    });
  }

  Widget buildListMessage() {
    getWidgetMessages(listMessage) {
      return ListView.builder(
          padding: EdgeInsets.all(10.0),
          itemCount: listMessage.length,
          reverse: true,
          controller: listScrollController,
          itemBuilder: (context, index) {
            print('List Length ======>>>>>> ${listMessage.length}');
            return GestureDetector(
                onLongPress: () {
                  deleteMessage();
                },
                child: buildItem(index, listMessage[index]));
          });
    }

    if (listMessage != null && listMessage.isNotEmpty) {
      return Flexible(child: getWidgetMessages(listMessage));
    }

    return Flexible(
      child: StreamBuilder(
        stream: getAllItems().asStream(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(
                child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(themeColor)));
          } else {
            listMessage = snapshot.data;
            return getWidgetMessages(listMessage);
          }
        },
      ),
    );
  }

  Future<List<CubeMessage>> getAllItems() async {
    Completer<List<CubeMessage>> completer = Completer();
    List<CubeMessage> messages;
    var params = GetMessagesParameters();
    params.sorter = RequestSorter(SORT_DESC, '', 'date_sent');
    try {
      await Future.wait<void>([
        getMessages(_cubeDialog.dialogId, params.getRequestParameters())
            .then((result) => messages = result.items),
        getAllUsersByIds(_cubeDialog.occupantsIds.toSet()).then((result) =>
            _occupants.addAll(Map.fromIterable(result.items,
                key: (item) => item.id, value: (item) => item)))
      ]);
      completer.complete(messages);
    } catch (error) {
      completer.completeError(error);
    }
    return completer.future;
  }

  Future<bool> onBackPress() {
    Navigator.of(context).popUntil(ModalRoute.withName("/SelectDialogScreen"));
    return Future.value(false);
  }

  @override
  void onCreateNotificationModelError(String res, String error) {
    print("error -> " + error);
  }

  @override
  void onCreateNotificationModelSuccess(res) {
    print("success -> " + res.toString() + " " + jsonDecode(res.body));
  }
}
