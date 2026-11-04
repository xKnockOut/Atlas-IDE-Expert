unit Atlas.Core.Tracker.YouTrackWorkflow;

// Karten im Board von YouTrack verschieben (#1272), ohne VCL und Open Tools
// API, unter Beachtung der Workflow-Regeln. Steuert eine Zustandsmaschine
// das Spaltenfeld ("StateMachineIssueCustomField"), lässt YouTrack ab dem
// aktuellen Wert nur bestimmte Übergänge zu ("possibleEvents"); ein Wert ohne
// Übergang wird abgelehnt ("No event found"). Das Board von YouTrack löst
// deshalb den passenden Übergang aus, statt den Wert zu setzen. Atlas macht
// es genauso:
// - Lesen: die Felder einer Karte bringen $type, id und possibleEvents(id,
//   presentation) mit (CardFieldParts in TAtlasYouTrackBoards.CardFields).
// - Auslösen: POST <url>/api/issues/<Kennung>/fields/<Feld-ID> mit
//   {"event": {"id": …, "presentation": …, "$type": "Event"}, "id": …,
//   "$type": "StateMachineIssueCustomField"}; ein Kommentar geht vorher als
//   eigener Kommentar hinaus, damit bei einem Fehler nichts halb geändert ist.
// - Ohne passenden Übergang (oder ohne Zustandsmaschine) ein Befehl je Wert
//   der Zielspalte: Lehnt YouTrack einen Wert ab (400, etwa weil eine Regel
//   nur einen anderen Wert einer zusammengefassten Spalte erlaubt), folgt der
//   nächste; bei anderen Fehlern nicht.
// Welcher Übergang in welche Spalte führt, entscheidet TAtlasBoardTransitions
// (Atlas.Core.Tracker.Board). Fehler aus Antworten von YouTrack liest
// TAtlasYouTrackErrors (auch für TAtlasYouTrackTracker).

interface

uses
  System.JSON,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Board;

type
  /// <summary>Fehler aus Antworten von YouTrack.</summary>
  TAtlasYouTrackErrors = class
  public
    /// <summary>Fehler zu einem HTTP-Status außer 200.</summary>
    class function OfStatus(AStatus: Integer): TAtlasCiFetchError; static;
    /// <summary>Fehlertext aus einer Antwort ("error_description", sonst "error"), gekürzt; '' ohne.</summary>
    class function Message(const AJson: string): string; static;
  end;

  /// <summary>Was beim Verschieben einer Karte geschrieben wird.</summary>
  TAtlasYouTrackMove = record
    Target: TAtlasTrackerTarget;
    /// <summary>Muss IAtlasCiSend können.</summary>
    Transport: IAtlasCiTransport;
    /// <summary>Schreibweg für Befehl und Kommentar (TAtlasYouTrackTracker, #1266).</summary>
    Writer: IAtlasTrackerWriter;
    /// <summary>'' = kein Kommentar.</summary>
    Comment: string;
    /// <summary>Zeitgrenze für alle Anfragen zusammen.</summary>
    TimeoutMs: Integer;
  end;

  TAtlasYouTrackWorkflow = class
  public const
    /// <summary>$type eines Feldes unter einer Zustandsmaschine.</summary>
    StateMachineType = 'StateMachineIssueCustomField';
    /// <summary>Felder, die eine Karte zusätzlich zu name und value je Feld braucht.</summary>
    CardFieldParts = 'id,possibleEvents(id,presentation)';
  public
    /// <summary>Regeln des Feldes AField aus customFields von AIssue (ohne Groß-/Kleinschreibung). Leer ohne
    /// Zustandsmaschine oder wenn die Antwort keine possibleEvents enthält (dann entscheidet YouTrack beim
    /// Verschieben).</summary>
    class function Find(AIssue: TJSONObject; const AField: string): TAtlasBoardWorkflow; static;
    /// <summary>Regeln eines einzelnen Feldes aus customFields.</summary>
    class function Parse(AField: TJSONObject): TAtlasBoardWorkflow; static;
    /// <summary>Adresse des Feldes AFieldId am Issue AKey; '' ohne Server oder bei ungültiger Kennung bzw. ID.
    /// </summary>
    class function FieldUrl(const ATarget: TAtlasTrackerTarget; const AKey, AFieldId: string): string; static;
    /// <summary>Inhalt des POST, der ATransition am Feld AFieldId auslöst.</summary>
    class function EventJson(const AFieldId: string; const ATransition: TAtlasBoardTransition): string; static;
    /// <summary>ACard in die Spalte AColumn von ASnapshot verschieben (Ablauf siehe Kopf der Unit).</summary>
    class function Move(const AMove: TAtlasYouTrackMove; const ASnapshot: TAtlasBoardSnapshot;
      const ACard: TAtlasBoardCard; AColumn: Integer): TAtlasTrackerWriteResult; static;
    /// <summary>Übergang ATransition der Zustandsmaschine von ACard auslösen, Kommentar vorher.</summary>
    class function Fire(const AMove: TAtlasYouTrackMove; const ACard: TAtlasBoardCard;
      ATransition: Integer): TAtlasTrackerWriteResult; static;
    /// <summary>Feld AField von AKey per Befehl auf einen Wert von AColumn setzen, der Reihe nach, bis YouTrack
    /// einen annimmt oder anders als mit 400 ablehnt; Kommentar im selben Befehl.</summary>
    class function SetValue(const AMove: TAtlasYouTrackMove; const AField, AKey: string;
      const AColumn: TAtlasBoardColumn): TAtlasTrackerWriteResult; static;
  end;

implementation

uses
  System.SysUtils,
  System.Diagnostics;

const
  /// <summary>Höchstlänge eines Fehlertextes.</summary>
  cMaxMessage = 300;

function TextOf(AObject: TJSONObject; const AName: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  mValue := AObject.Values[AName];
  if mValue is TJSONString then
  begin
    Result := TJSONString(mValue).Value;
  end;
end;

/// <summary>Nur Buchstaben, Ziffern, '-' und '_', nicht leer (Kennung "ATL-123", Feld-ID "82-11").</summary>
function ValidPart(const AText: string): Boolean;
var
  mChar: Char;
begin
  Result := AText <> '';
  for mChar in AText do
  begin
    Result := Result and CharInSet(mChar, ['A'..'Z', 'a'..'z', '0'..'9', '-', '_']);
  end;
end;

/// <summary>Restzeit von ATimeoutMs seit dem Start von AWatch; nie negativ.</summary>
function Rest(const AWatch: TStopwatch; ATimeoutMs: Integer): Integer;
var
  mRest: Int64;
begin
  mRest := ATimeoutMs - AWatch.ElapsedMilliseconds;
  Result := 0;
  if mRest > 0 then
  begin
    Result := Integer(mRest);
  end;
end;

{ TAtlasYouTrackErrors }

class function TAtlasYouTrackErrors.OfStatus(AStatus: Integer): TAtlasCiFetchError;
begin
  case AStatus of
    401, 403:
      Result := TAtlasCiFetchError.Unauthorized;
    404:
      Result := TAtlasCiFetchError.NotFound;
    400:
      Result := TAtlasCiFetchError.Invalid;
  else
    Result := TAtlasCiFetchError.Server;
  end;
end;

class function TAtlasYouTrackErrors.Message(const AJson: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if mValue is TJSONObject then
    begin
      Result := TextOf(TJSONObject(mValue), 'error_description');
      if Result = '' then
      begin
        Result := TextOf(TJSONObject(mValue), 'error');
      end;
    end;
  finally
    mValue.Free;
  end;
  Result := Trim(StringReplace(StringReplace(Result, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]));
  if Length(Result) > cMaxMessage then
  begin
    Result := Copy(Result, 1, cMaxMessage - 1) + '…';
  end;
end;

{ TAtlasYouTrackWorkflow }

class function TAtlasYouTrackWorkflow.Parse(AField: TJSONObject): TAtlasBoardWorkflow;
var
  mEvents, mItem: TJSONValue;
  mId: string;
begin
  Result := Default(TAtlasBoardWorkflow);
  mEvents := AField.Values['possibleEvents'];
  if not SameText(TextOf(AField, '$type'), StateMachineType) or not (mEvents is TJSONArray) then
  begin
    Exit;
  end;
  Result.StateMachine := True;
  Result.FieldId := TextOf(AField, 'id');
  for mItem in TJSONArray(mEvents) do
  begin
    if mItem is TJSONObject then
    begin
      mId := TextOf(TJSONObject(mItem), 'id');
      if mId <> '' then
      begin
        Result.Transitions := Result.Transitions +
          [TAtlasBoardTransition.Create(mId, TextOf(TJSONObject(mItem), 'presentation'))];
      end;
    end;
  end;
end;

class function TAtlasYouTrackWorkflow.Find(AIssue: TJSONObject; const AField: string): TAtlasBoardWorkflow;
var
  mFields, mItem: TJSONValue;
begin
  Result := Default(TAtlasBoardWorkflow);
  mFields := AIssue.Values['customFields'];
  if (AField = '') or not (mFields is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(mFields) do
  begin
    if (mItem is TJSONObject) and SameText(Trim(TextOf(TJSONObject(mItem), 'name')), AField) then
    begin
      Exit(Parse(TJSONObject(mItem)));
    end;
  end;
end;

class function TAtlasYouTrackWorkflow.FieldUrl(const ATarget: TAtlasTrackerTarget;
  const AKey, AFieldId: string): string;
begin
  Result := '';
  if (ATarget.Server <> '') and ValidPart(Trim(AKey)) and ValidPart(AFieldId) then
  begin
    Result := ATarget.Url + '/api/issues/' + Trim(AKey) + '/fields/' + AFieldId + '?fields=id';
  end;
end;

class function TAtlasYouTrackWorkflow.EventJson(const AFieldId: string;
  const ATransition: TAtlasBoardTransition): string;
var
  mObject, mEvent: TJSONObject;
begin
  mObject := TJSONObject.Create;
  try
    mEvent := TJSONObject.Create;
    mEvent.AddPair('id', ATransition.Id);
    mEvent.AddPair('presentation', ATransition.Name);
    mEvent.AddPair('$type', 'Event');
    mObject.AddPair('event', mEvent);
    mObject.AddPair('id', AFieldId);
    mObject.AddPair('$type', StateMachineType);
    Result := mObject.ToJSON;
  finally
    mObject.Free;
  end;
end;

class function TAtlasYouTrackWorkflow.Move(const AMove: TAtlasYouTrackMove; const ASnapshot: TAtlasBoardSnapshot;
  const ACard: TAtlasBoardCard; AColumn: Integer): TAtlasTrackerWriteResult;
var
  mTransition: Integer;
begin
  Result := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, 0, '');
  if (AColumn < 0) or (AColumn > High(ASnapshot.Columns)) or (Length(ASnapshot.Columns[AColumn].Values) = 0) then
  begin
    Exit;
  end;
  mTransition := TAtlasBoardTransitions.Into(ACard, ASnapshot.Columns[AColumn]);
  if ACard.Workflow.StateMachine and (mTransition >= 0) and (ACard.Workflow.FieldId <> '') then
  begin
    Result := Fire(AMove, ACard, mTransition);
  end
  else
  begin
    Result := SetValue(AMove, ASnapshot.Field, ACard.Key, ASnapshot.Columns[AColumn]);
  end;
end;

class function TAtlasYouTrackWorkflow.Fire(const AMove: TAtlasYouTrackMove; const ACard: TAtlasBoardCard;
  ATransition: Integer): TAtlasTrackerWriteResult;
var
  mWatch: TStopwatch;
  mSend: IAtlasCiSend;
  mChange: TAtlasTrackerWrite;
  mUrl, mAnswer: string;
  mStatus: Integer;
  mError: TAtlasCiFetchError;
begin
  Result := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotConfigured, 0, '');
  mUrl := FieldUrl(AMove.Target, ACard.Key, ACard.Workflow.FieldId);
  if (mUrl = '') or (AMove.Writer = nil) or not Supports(AMove.Transport, IAtlasCiSend, mSend) then
  begin
    Exit;
  end;
  mWatch := TStopwatch.StartNew;
  Result := TAtlasTrackerWriteResult.Ok;
  if Trim(AMove.Comment) <> '' then
  begin
    mChange := TAtlasTrackerWrite.Empty;
    mChange.Comment := AMove.Comment;
    Result := AMove.Writer.Apply(AMove.Target, AMove.Transport, ACard.Key, mChange, AMove.TimeoutMs);
  end;
  if not Result.Succeeded then
  begin
    Exit;
  end;
  if not mSend.Send('POST', mUrl, EventJson(ACard.Workflow.FieldId, ACard.Workflow.Transitions[ATransition]),
    Rest(mWatch, AMove.TimeoutMs), mStatus, mAnswer, mError) then
  begin
    Result := TAtlasTrackerWriteResult.Failed(mError, 0, '');
  end
  else if (mStatus < 200) or (mStatus > 299) then
  begin
    Result := TAtlasTrackerWriteResult.Failed(TAtlasYouTrackErrors.OfStatus(mStatus), mStatus,
      TAtlasYouTrackErrors.Message(mAnswer));
  end;
end;

class function TAtlasYouTrackWorkflow.SetValue(const AMove: TAtlasYouTrackMove; const AField, AKey: string;
  const AColumn: TAtlasBoardColumn): TAtlasTrackerWriteResult;
var
  mWatch: TStopwatch;
  mChange: TAtlasTrackerWrite;
  mValue: string;
begin
  Result := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotConfigured, 0, '');
  if AMove.Writer = nil then
  begin
    Exit;
  end;
  mWatch := TStopwatch.StartNew;
  for mValue in AColumn.Values do
  begin
    mChange := TAtlasTrackerWrite.Empty;
    mChange.StateField := AField;
    mChange.State := mValue;
    mChange.Comment := AMove.Comment;
    Result := AMove.Writer.Apply(AMove.Target, AMove.Transport, AKey, mChange, Rest(mWatch, AMove.TimeoutMs));
    if Result.Succeeded or (Result.Error <> TAtlasCiFetchError.Invalid) then
    begin
      Break;
    end;
  end;
end;

end.
