unit Atlas.Core.Tracker.Contract.Sprint;

// Vertrag der Sprint-Kachel (#1277, #1443): TAtlasSprintView, was die Kachel
// vom Sprint zeigt. Berechnet in Atlas.Core.Tracker.Sprint, gezeigt über
// Atlas.UI.Tracker.Contract.Sprint.

interface

uses
  Atlas.Core.Tracker.Contract;

type
  TAtlasSprintView = record
    /// <summary>Ein Sprint mit Zeitraum ist da.</summary>
    Known: Boolean;
    Name: string;
    Start: TDateTime;
    Finish: TDateTime;
    /// <summary>Board im Browser; '' unbekannt.</summary>
    Page: string;
    DayCount: Integer;
    /// <summary>Arbeitstage des Sprints (Datum, UTC); Tag k des Diagramms endet mit Dates[k - 1].</summary>
    Dates: TArray<TDateTime>;
    DaysLeft: Integer;
    /// <summary>Arbeitstage bis heute (Ist-Linie hat Today + 1 Punkte).</summary>
    Today: Integer;
    UsesPoints: Boolean;
    /// <summary>Anmeldename bekannt: Zahlen „meine …“ gelten.</summary>
    MineKnown: Boolean;
    MineOpen: TArray<TAtlasTrackerIssue>;
    MineDone: TArray<TAtlasTrackerIssue>;
    Total: Double;
    TeamDone: Double;
    TeamLeft: Double;
    /// <summary>Rest nach k Arbeitstagen, k = 0 … Today.</summary>
    Actual: TArray<Double>;
    /// <summary>Ideallinie, k = 0 … DayCount.</summary>
    Ideal: TArray<Double>;
    HasPrevious: Boolean;
    PreviousName: string;
    /// <summary>Rest des Vorsprints auf diesen Sprint normiert und auf Total skaliert, k = 0 … DayCount.</summary>
    Previous: TArray<Double>;
    /// <summary>Erledigt im Vorsprint am selben Sprinttag (in seiner Einheit).</summary>
    PreviousDone: Double;
    /// <summary>Erledigt in diesem Sprint bis heute (Done[Today]).</summary>
    DoneToday: Double;
    /// <summary>Velocity der letzten Sprints, ältester zuerst (höchstens drei).</summary>
    Velocity: TArray<Double>;
    VelocityNames: TArray<string>;
    Fetched: TDateTime;
  end;

implementation

end.
