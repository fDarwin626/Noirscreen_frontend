import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/scheduled_room_model.dart';
import '../services/rooms_service.dart';

// Rooms service singleton
final roomsServiceProvider = Provider((ref) => RoomsService());

// All scheduled rooms for current user
// Ordered by scheduled_at — most recent first
final scheduledRoomsProvider = FutureProvider.autoDispose<List<ScheduledRoomModel>>(
  (ref) async {
    print('🔄 PROVIDER: scheduledRoomsProvider called');
    final service = ref.watch(roomsServiceProvider);
    final rooms = await service.getScheduledRooms();
    print('✅ PROVIDER: scheduledRoomsProvider returned ${rooms.length} rooms');
    return rooms;
  },
);
