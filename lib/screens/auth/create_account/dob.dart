import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:talksy/screens/auth/entryscreen.dart';

import 'gender.dart';

class DobScreen extends StatefulWidget {
  final String firstName;
  final String lastName;
  final File? profileImage;

  const DobScreen({
    super.key,
    required this.firstName,
    required this.lastName,
    this.profileImage,
  });

  static Route route({
    required String firstName,
    required String lastName,
    File? profileImage,
  }) {
    // CupertinoPageRoute bata MaterialPageRoute ma change gareko,
    // yesle main.dart ko theme follow garxa.
    return MaterialPageRoute(
      builder: (_) => DobScreen(
        firstName: firstName,
        lastName: lastName,
        profileImage: profileImage,
      ),
    );
  }

  @override
  State<DobScreen> createState() => _DobScreenState();
}

class _DobScreenState extends State<DobScreen> {
  DateTime? _selectedDate;

  bool _isButtonEnabled = false;

  int? _selectedDay;
  int? _selectedMonth;
  int? _selectedYear;

  late final List<int> _years;

  final List<int> _months = List.generate(12, (index) => index + 1);

  List<int> get _days {
    final month = _selectedMonth ?? 1;
    final year = _selectedYear ?? DateTime.now().year;

    final daysInMonth = DateTime(year, month + 1, 0).day;

    return List.generate(daysInMonth, (index) => index + 1);
  }

  String get _selectedDateText {
    if (_selectedDate == null) {
      return 'Select Date';
    }

    return DateFormat('MMMM dd, yyyy').format(_selectedDate!);
  }

  @override
  void initState() {
    super.initState();

    final currentYear = DateTime.now().year;

    _years = List.generate(
      currentYear - 1900 + 1,
      (index) => 1900 + index,
    ).reversed.toList();

    final defaultDate = DateTime(
      DateTime.now().year - 13,
      DateTime.now().month,
      DateTime.now().day,
    );

    _selectedYear = defaultDate.year;
    _selectedMonth = defaultDate.month;
    _selectedDay = defaultDate.day;

    _updateSelectedDateFromComponents();
  }

  int _calculateAge(DateTime birthDate) {
    final today = DateTime.now();

    int age = today.year - birthDate.year;

    if (today.month < birthDate.month ||
        (today.month == birthDate.month && today.day < birthDate.day)) {
      age--;
    }

    return age;
  }

  void _updateSelectedDateFromComponents() {
    if (_selectedYear != null &&
        _selectedMonth != null &&
        _selectedDay != null) {
      final maxDay = DateTime(_selectedYear!, _selectedMonth! + 1, 0).day;

      final day = _selectedDay! > maxDay ? maxDay : _selectedDay!;

      final candidate = DateTime(_selectedYear!, _selectedMonth!, day);

      setState(() {
        _selectedDate = candidate;
        _selectedDay = day;
        _isButtonEnabled = _calculateAge(candidate) >= 13;
      });
    } else {
      setState(() {
        _selectedDate = null;
        _isButtonEnabled = false;
      });
    }
  }

  void _onNextClicked() {
    if (!_isButtonEnabled || _selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must be at least 13 years old.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    // MaterialPageRoute use garne consistency ko lagi
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GenderScreen(
          firstName: widget.firstName,
          lastName: widget.lastName,
          profileImage: widget.profileImage,
          dob: _selectedDate!,
        ),
      ),
    );
  }

  Widget _buildCompactPicker(BuildContext context) {
    final cardColor = Theme.of(context).cardColor;

    final textColor = Theme.of(context).textTheme.bodyLarge?.color;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _selectedDate == null ? 'Select Date' : _selectedDateText,
            style: TextStyle(
              fontSize: 16,
              color: _selectedDate == null ? Colors.grey.shade600 : textColor,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: DropdownButton<int>(
                      value: _selectedDay,
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      items: _days.map((day) {
                        return DropdownMenuItem<int>(
                          value: day,
                          child: Text(day.toString()),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedDay = value;
                        });

                        _updateSelectedDateFromComponents();
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: DropdownButton<int>(
                      value: _selectedMonth,
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      items: _months.map((month) {
                        return DropdownMenuItem<int>(
                          value: month,
                          child: Text(
                            DateFormat.MMMM().format(DateTime(0, month)),
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedMonth = value;
                        });

                        _updateSelectedDateFromComponents();
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: DropdownButton<int>(
                      value: _selectedYear,
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      items: _years.map((year) {
                        return DropdownMenuItem<int>(
                          value: year,
                          child: Text(year.toString()),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedYear = value;
                        });

                        _updateSelectedDateFromComponents();
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final disabledBg = isDark ? Colors.grey.shade700 : Colors.grey.shade300;

    final disabledFg = isDark ? Colors.grey.shade400 : Colors.grey.shade600;

    return Scaffold(
      backgroundColor: backgroundColor,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        toolbarHeight: 40,
        leading: const BackButton(),
        titleSpacing: 0,
        centerTitle: false,
        title: const Text('Choose Date'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              const Text(
                'When is your birthday?',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                'Choose your date of birth. You can always make this private later.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 20),

              _buildCompactPicker(context),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isButtonEnabled ? _onNextClicked : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isButtonEnabled
                        ? AppTheme.primary
                        : disabledBg,
                    foregroundColor: _isButtonEnabled
                        ? Colors.white
                        : disabledFg,
                    disabledBackgroundColor: disabledBg,
                    disabledForegroundColor: disabledFg,
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    surfaceTintColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Next',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
