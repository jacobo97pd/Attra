import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../data/friend_group_service.dart';
import '../domain/group_message.dart';
import 'group_avatar.dart';

/// Chat de un grupo (Modo Amigos). Solo los miembros pueden leer y escribir
/// (validado por reglas). Mensajes propios a la derecha, ajenos a la izquierda
/// con el nombre del emisor.
class GroupChatScreen extends StatefulWidget {
  const GroupChatScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.currentUid,
    required this.currentUserName,
    required this.service,
    this.groupPhotoUrl = '',
  });

  final String groupId;
  final String groupName;
  final String currentUid;
  final String currentUserName;
  final FriendGroupService service;
  final String groupPhotoUrl;

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final TextEditingController _input = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final String text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _input.clear();
    try {
      await widget.service.sendGroupMessage(
        widget.groupId,
        senderId: widget.currentUid,
        senderName: widget.currentUserName.isEmpty
            ? 'Alguien'
            : widget.currentUserName,
        text: text,
      );
    } catch (_) {
      if (mounted) {
        _input.text = text; // recupera el texto si falla
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo enviar el mensaje.')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        titleSpacing: 0,
        title: Row(
          children: <Widget>[
            GroupAvatar(
                photoUrl: widget.groupPhotoUrl, size: 36, circle: true),
            const SizedBox(width: 10),
            Expanded(
              child: Text(widget.groupName,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: StreamBuilder<List<GroupMessage>>(
              stream: widget.service.observeGroupMessages(widget.groupId),
              builder: (BuildContext context,
                  AsyncSnapshot<List<GroupMessage>> snap) {
                if (snap.hasError) {
                  return _centered('No se pudo cargar el chat.\n${snap.error}');
                }
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.attraRed));
                }
                final List<GroupMessage> msgs =
                    snap.data ?? const <GroupMessage>[];
                if (msgs.isEmpty) {
                  return _centered(
                      'Aún no hay mensajes.\n¡Rompe el hielo con tu grupo!');
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  itemCount: msgs.length,
                  itemBuilder: (BuildContext context, int i) {
                    final GroupMessage m = msgs[i];
                    final bool mine = m.senderId == widget.currentUid;
                    final bool showName = !mine &&
                        (i == 0 || msgs[i - 1].senderId != m.senderId);
                    return _Bubble(message: m, mine: mine, showName: showName);
                  },
                );
              },
            ),
          ),
          _composer(context),
        ],
      ),
    );
  }

  Widget _centered(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 14)),
        ),
      );

  Widget _composer(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        color: AppColors.surface,
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Escribe al grupo…',
                  hintStyle: const TextStyle(color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.black,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _sending ? null : _send,
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: AppColors.action),
                  ),
                  child: _sending
                      ? const Padding(
                          padding: EdgeInsets.all(13),
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send, color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(
      {required this.message, required this.mine, required this.showName});
  final GroupMessage message;
  final bool mine;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: <Widget>[
          if (showName)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 2),
              child: Text(message.senderName,
                  style: const TextStyle(
                      color: AppColors.attraRed,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ),
          Container(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: mine
                  ? const LinearGradient(colors: AppColors.action)
                  : null,
              color: mine ? null : AppColors.surface,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(mine ? 16 : 4),
                bottomRight: Radius.circular(mine ? 4 : 16),
              ),
              border: mine
                  ? null
                  : Border.all(color: AppColors.surfaceLine),
            ),
            child: Text(message.text,
                style: TextStyle(
                    color: mine ? Colors.white : AppColors.textPrimary,
                    fontSize: 15)),
          ),
        ],
      ),
    );
  }
}
