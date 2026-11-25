unit Atlas.Core.Tracker.PreviewLoad;

// Ablauf des Ladens im Fenster „Atlas-Issue“ (#1264) ohne IDE prüfbar:
// - Eine Abfrage zur Zeit: Ein Wunsch, während eine Abfrage läuft, merkt sich
//   vor (ein späterer ersetzt ihn) und bricht die laufende ab. Kommt deren
//   Antwort, zählt sie nicht; der vorgemerkte Wunsch folgt.
// - Antworten werden über die Generation eingeordnet: Nur die Antwort der
//   laufenden Abfrage beendet sie; eine fremde (verspätete) Antwort ist
//   veraltet und lässt Lauf und Abbruch der laufenden unberührt.
// - Abbrechen vergisst den vorgemerkten Wunsch und erreicht nur eine laufende
//   Abfrage.
// Zeigen, Abfrage im Hintergrund und Abbruch-Griff übernimmt der Lader
// (TAtlasIssueLoader): in der IDE Atlas.IDE.Tracker.IssueLoad, in den Tests
// eine Fälschung. Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  Atlas.Plugin.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Preview;

type
  /// <summary>Antwort einer Abfrage der Vorschau.</summary>
  TAtlasIssueLoadAnswer = record
    /// <summary>Generation, unter der die Abfrage gestartet wurde.</summary>
    Generation: Integer;
    Entry: TAtlasIssueHistoryEntry;
    Succeeded: Boolean;
    Details: TAtlasTrackerDetails;
    Error: TAtlasCiFetchError;
    class function Create(AGeneration: Integer; const AEntry: TAtlasIssueHistoryEntry; ASucceeded: Boolean;
      const ADetails: TAtlasTrackerDetails; AError: TAtlasCiFetchError): TAtlasIssueLoadAnswer; static;
    /// <summary>Keine Antwort mit Grund AError.</summary>
    class function Failed(AGeneration: Integer; const AEntry: TAtlasIssueHistoryEntry;
      AError: TAtlasCiFetchError): TAtlasIssueLoadAnswer; static;
  end;

  /// <summary>AEntry zeigen (letzter Stand) und seine Abfrage im Hintergrund starten; AGeneration ist die neue
  /// Generation. False, wenn keine Abfrage startet (AError nennt den Grund, etwa ein fehlendes Token).</summary>
  TAtlasIssueLoaderStart = reference to function(const AEntry: TAtlasIssueHistoryEntry; out AGeneration: Integer;
    out AError: TAtlasCiFetchError): Boolean;
  /// <summary>Antwort AAnswer ist eingeordnet: AStep sagt, was mit ihr geschieht.</summary>
  TAtlasIssueLoaderArrived = reference to procedure(const AAnswer: TAtlasIssueLoadAnswer;
    AStep: TAtlasIssueLoadStep);

  /// <summary>Was der Ablauf vom Lader braucht.</summary>
  TAtlasIssueLoader = record
    Start: TAtlasIssueLoaderStart;
    /// <summary>Die laufende Abfrage abbrechen; ihre Antwort kommt trotzdem (abgebrochen).</summary>
    Cancel: TProc;
    /// <summary>Die laufende Abfrage ist zu Ende: Abbruch-Griff und Thread freigeben.</summary>
    Ended: TProc;
    /// <summary>Generation des jüngsten Wunsches (ändert sich auch beim Abmelden).</summary>
    Generation: TFunc<Integer>;
    Arrived: TAtlasIssueLoaderArrived;
  end;

  TAtlasIssueLoadFlow = class
  private
    FLoader: TAtlasIssueLoader;
    FRunning: Boolean;
    FRunningGeneration: Integer;
    FPending: TAtlasIssueHistoryEntry;
    FHasPending: Boolean;
    procedure Arrive(const AAnswer: TAtlasIssueLoadAnswer; AStep: TAtlasIssueLoadStep);
  public
    constructor Create(const ALoader: TAtlasIssueLoader);
    /// <summary>AEntry laden; läuft schon eine Abfrage, wird sie abgebrochen und dieser Wunsch folgt ihr.</summary>
    procedure Request(const AEntry: TAtlasIssueHistoryEntry);
    /// <summary>Antwort einer Abfrage (Hauptthread).</summary>
    procedure Finished(const AAnswer: TAtlasIssueLoadAnswer);
    /// <summary>Laufende Abfrage abbrechen, wartenden Wunsch vergessen.</summary>
    procedure Cancel;
    /// <summary>Alle Abfragen sind abgewartet (Abmelden): nichts läuft, nichts wartet; spätere Antworten sind
    /// veraltet.</summary>
    procedure Reset;
    /// <summary>Eine Abfrage läuft.</summary>
    property Running: Boolean read FRunning;
    /// <summary>Ein Wunsch wartet auf das Ende der laufenden Abfrage.</summary>
    property HasPending: Boolean read FHasPending;
  end;

implementation

{ TAtlasIssueLoadAnswer }

class function TAtlasIssueLoadAnswer.Create(AGeneration: Integer; const AEntry: TAtlasIssueHistoryEntry;
  ASucceeded: Boolean; const ADetails: TAtlasTrackerDetails; AError: TAtlasCiFetchError): TAtlasIssueLoadAnswer;
begin
  Result.Generation := AGeneration;
  Result.Entry := AEntry;
  Result.Succeeded := ASucceeded;
  Result.Details := ADetails;
  Result.Error := AError;
end;

class function TAtlasIssueLoadAnswer.Failed(AGeneration: Integer; const AEntry: TAtlasIssueHistoryEntry;
  AError: TAtlasCiFetchError): TAtlasIssueLoadAnswer;
begin
  Result := Create(AGeneration, AEntry, False, TAtlasTrackerDetails.Empty, AError);
end;

{ TAtlasIssueLoadFlow }

constructor TAtlasIssueLoadFlow.Create(const ALoader: TAtlasIssueLoader);
begin
  inherited Create;
  FLoader := ALoader;
end;

procedure TAtlasIssueLoadFlow.Arrive(const AAnswer: TAtlasIssueLoadAnswer; AStep: TAtlasIssueLoadStep);
begin
  if Assigned(FLoader.Arrived) then
  begin
    FLoader.Arrived(AAnswer, AStep);
  end;
end;

procedure TAtlasIssueLoadFlow.Request(const AEntry: TAtlasIssueHistoryEntry);
var
  mGeneration: Integer;
  mError: TAtlasCiFetchError;
begin
  if FRunning then
  begin
    FPending := AEntry;
    FHasPending := True;
    if Assigned(FLoader.Cancel) then
    begin
      FLoader.Cancel();
    end;
    Exit;
  end;
  mGeneration := 0;
  mError := TAtlasCiFetchError.Network;
  if FLoader.Start(AEntry, mGeneration, mError) then
  begin
    FRunning := True;
    FRunningGeneration := mGeneration;
    Exit;
  end;
  // Keine Abfrage (etwa ohne Token): gleich als Fehler dieses Wunsches zeigen.
  Arrive(TAtlasIssueLoadAnswer.Failed(mGeneration, AEntry, mError),
    TAtlasIssuePreview.LoadStep(False, mGeneration, FLoader.Generation(), False));
end;

procedure TAtlasIssueLoadFlow.Finished(const AAnswer: TAtlasIssueLoadAnswer);
var
  mStep: TAtlasIssueLoadStep;
begin
  if not FRunning or (AAnswer.Generation <> FRunningGeneration) then
  begin
    // Antwort einer Abfrage, die nicht mehr läuft: Die laufende bleibt, wie sie ist.
    Arrive(AAnswer, TAtlasIssueLoadStep.Outdated);
    Exit;
  end;
  FRunning := False;
  if Assigned(FLoader.Ended) then
  begin
    FLoader.Ended();
  end;
  mStep := TAtlasIssuePreview.LoadStep(FHasPending, AAnswer.Generation, FLoader.Generation(), AAnswer.Succeeded);
  Arrive(AAnswer, mStep);
  if mStep = TAtlasIssueLoadStep.Pending then
  begin
    // Ein anderer Wunsch wartet: der zählt.
    FHasPending := False;
    Request(FPending);
  end;
end;

procedure TAtlasIssueLoadFlow.Cancel;
begin
  FHasPending := False;
  if FRunning and Assigned(FLoader.Cancel) then
  begin
    FLoader.Cancel();
  end;
end;

procedure TAtlasIssueLoadFlow.Reset;
begin
  FRunning := False;
  FHasPending := False;
end;

end.
