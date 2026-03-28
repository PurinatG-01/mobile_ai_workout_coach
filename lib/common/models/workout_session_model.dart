class WorkOutSession {
  final String id;
  final String name;
  final DateTime startDate;
  final DateTime? endDate;
  final List<WorkOutSet> sets;

  WorkOutSession(this.id, this.name, this.startDate, this.endDate, this.sets);
}

class WorkOutSet {
  final String name;
  final int reps;
  final DateTime startTime;
  final DateTime? endTime;

  WorkOutSet(this.name, this.reps, this.startTime, this.endTime);
}
