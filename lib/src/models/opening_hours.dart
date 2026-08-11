class OpeningHours {
  const OpeningHours({
    required this.weekdayOpen,
    required this.weekdayClose,
    this.saturdayOpen,
    this.saturdayClose,
    this.sundayOpen,
    this.sundayClose,
  });

  final int weekdayOpen;
  final int weekdayClose;
  final int? saturdayOpen;
  final int? saturdayClose;
  final int? sundayOpen;
  final int? sundayClose;

  bool isOpenAt(DateTime time) {
    final hour = time.hour;
    switch (time.weekday) {
      case DateTime.saturday:
        return _isWithin(hour, saturdayOpen, saturdayClose);
      case DateTime.sunday:
        return _isWithin(hour, sundayOpen, sundayClose);
      default:
        return hour >= weekdayOpen && hour < weekdayClose;
    }
  }

  String get summary {
    final weekday = 'Mon-Fri ${_format(weekdayOpen)}-${_format(weekdayClose)}';
    final saturday = saturdayOpen == null || saturdayClose == null
        ? 'Sat closed'
        : 'Sat ${_format(saturdayOpen!)}-${_format(saturdayClose!)}';
    final sunday = sundayOpen == null || sundayClose == null
        ? 'Sun closed'
        : 'Sun ${_format(sundayOpen!)}-${_format(sundayClose!)}';
    return '$weekday - $saturday - $sunday';
  }

  bool _isWithin(int hour, int? open, int? close) {
    if (open == null || close == null) {
      return false;
    }
    return hour >= open && hour < close;
  }

  String _format(int hour) => '${hour.toString().padLeft(2, '0')}:00';
}
