class BookingPackingList {
  final String id;
  final String bookingId;
  final String storagePath;
  final String fileName;
  final DateTime uploadedAt;
  final String uploadedBy;

  const BookingPackingList({
    required this.id,
    required this.bookingId,
    required this.storagePath,
    required this.fileName,
    required this.uploadedAt,
    required this.uploadedBy,
  });

  factory BookingPackingList.fromMap(Map<String, dynamic> map) {
    return BookingPackingList(
      id: map['id'] as String,
      bookingId: map['booking_id'] as String,
      storagePath: map['storage_path'] as String,
      fileName: map['file_name'] as String,
      uploadedAt: DateTime.parse(map['uploaded_at'] as String),
      uploadedBy: map['uploaded_by'] as String,
    );
  }
}
