import 'dart:io';

import 'package:agora_project/models/chat_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

class ChatController extends GetxController {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  late FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;

  final String currentUserId;
  final String doctorId;
  final String conversationId;

  ChatController(this.doctorId, this.currentUserId)
      : conversationId = '${doctorId}_${currentUserId}';

  var messages = <ChatModel>[].obs;
  var isLoading = false.obs;
  RxDouble? progress = 0.0.obs;

  @override
  void onInit() {
    super.onInit();
    initNotifications();
    getMessages();
  }

  Future<void> sendImageFromGallery() async {
    await _sendFile(ImageSource.gallery, 'image');
  }

  Future<void> sendImageFromCamera() async {
    await _sendFile(ImageSource.camera, 'image');
  }

  Future<void> sendPdfFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null && result.files.isNotEmpty) {
      File file = File(result.files.single.path!);
      await _sendFile(file, 'pdf');
    } else {
      // User canceled the picker
      Get.snackbar('Error', 'No PDF selected');
    }
  }

  Future<void> _sendFile(dynamic source, String type) async {
    File? file;
    String? fileName;

    if (type == 'image') {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: source);
      if (image == null) return;
      file = File(image.path);
      fileName = 'chat_files/${DateTime.now().millisecondsSinceEpoch}.jpg';
    } else if (type == 'pdf') {
      if (source is File) {
        file = source;
        fileName = 'chat_files/${DateTime.now().millisecondsSinceEpoch}.pdf';
      } else {
        Get.snackbar('Error', 'Invalid PDF source');
        return;
      }
    }

    if (file == null || fileName == null) {
      Get.snackbar('Error', 'No file selected');
      return;
    }

    try {
      final Reference storageRef = FirebaseStorage.instance.ref().child(fileName);
      final UploadTask uploadTask = storageRef.putFile(file);

      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        double progress = snapshot.bytesTransferred.toDouble() / snapshot.totalBytes.toDouble();
        this.progress?.value = progress;
        Get.snackbar('Upload Progress', 'Uploading: ${(progress * 100).toStringAsFixed(2)}%');
      });

      final TaskSnapshot snapshot = await uploadTask;
      final String downloadUrl = await snapshot.ref.getDownloadURL();

      await _firestore.collection('Conversation')
          .doc(conversationId)
          .collection('Chats')
          .add({
        'sender_id': currentUserId,
        'receiver_id': doctorId,
        'date_time': FieldValue.serverTimestamp(),
        'type': type,
        type == 'image' ? 'image_url' : 'pdf_url': downloadUrl,
      });
    } catch (e) {
      Get.snackbar('Error', 'Failed to send file: ${e.toString()}');
    }
  }

  void initNotifications() {
    flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    final InitializationSettings initializationSettings =
    InitializationSettings(android: initializationSettingsAndroid);

    flutterLocalNotificationsPlugin.initialize(initializationSettings);

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        showNotification(
          message.notification!.title ?? 'New Message',
          message.notification!.body ?? '',
        );
      }
    });

    _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  void showNotification(String title, String body) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
    AndroidNotificationDetails(
      'your_channel_id',
      'Chat Notifications',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: false,
    );

    const NotificationDetails platformChannelSpecifics =
    NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      0,
      title,
      body,
      platformChannelSpecifics,
      payload: 'chat',
    );
  }

  Stream<QuerySnapshot> getMessagesStream() {
    return _firestore
        .collection('Conversation')
        .doc(conversationId)
        .collection('Chats')
        .orderBy('date_time', descending: false)
        .snapshots();
  }

  void getMessages() {
    isLoading(true);
    getMessagesStream().listen((querySnapshot) {
      messages.assignAll(querySnapshot.docs.map((doc) {
        return ChatModel.fromFirestore(doc, progress!);
      }).toList());
      isLoading(false);
    });
  }

  Future<void> sendMessage(String text) async {
    if (text
        .trim()
        .isEmpty) return;

    final newMessage = {
      'date_time': DateTime.now(),
      'sender_id': currentUserId,
      'receiver_id': doctorId,
      'text': text,
      'type': 'text',
    };

    try {
      await _firestore
          .collection('Conversation')
          .doc(conversationId)
          .collection('Chats')
          .add(newMessage);

      await sendPushNotification(
        doctorId,
        'New Message',
        text,
      );
    } catch (e) {
      Get.snackbar('Error', 'Failed to send message');
    }
  }

  Future<void> sendPushNotification(String receiverId, String title,
      String body) async {
    print('Notification would be sent to $receiverId: $title - $body');
  }
}