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
// (Atlas.Core.Tracker.Board); Befehle, Status und Fehlertexte über
// TAtlasYouTrackApi.

interface

uses
  System.JSON,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Board;

type
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
    /// <summary>AMove.Card in die Spalte AMove.Column von ASnapshot verschieben (Ablauf siehe Kopf der Unit).
    /// </summary>
    class function Move(const AMove: TAtlasBoardMove; const ASnapshot: TAtlasBoardSnapshot): TAtlasTrackerWriteResult;
      static;
    /// <summary>Übergang ATransition der Zustandsmaschine von AMove.Card auslösen, Kommentar vorher.</summary>
    class function Fire(const AMove: TAtlasBoardMove; ATransition: Integer): TAtlasTrackerWriteResult; static;
    /// <summary>Feld AField von AMove.Card per Befehl auf einen Wert von AColumn setzen, der Reihe nach, bis
    /// YouTrack einen annimmt oder anders als mit 400 ablehnt; Kommentar im selben Befehl.</summary>
    class function SetValue(const AMove: TAtlasBoardMove; const AField: string;
      const AColumn: TAtlasBoardColumn): TAtlasTrackerWriteResult; static;
  end;

implementation

uses
  System.SysUtils,
  System.Diagnostics,
  Atlas.Core.Tracker.YouTrackApi;

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

class function TAtlasYouTrackWorkflow.Move(const AMove: TAtlasBoardMove;
  const ASnapshot: TAtlasBoardSnapshot): TAtlasTrackerWriteResult;
var
  mTransition: Integer;
begin
  Result := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, 0, '');
  if (AMove.Column < 0) or (AMove.Column > High(ASnapshot.Columns))
    or (Length(ASnapshot.Columns[AMove.Column].Values) = 0) then
  begin
    Exit;
  end;
  mTransition := TAtlasBoardTransitions.Into(AMove.Card, ASnapshot.Columns[AMove.Column]);
  if AMove.Card.Workflow.StateMachine and (mTransition >= 0) and (AMove.Card.Workflow.FieldId <> '') then
  begin
    Result := Fire(AMove, mTransition);
  end
  else
  begin
    Result := SetValue(AMove, ASnapshot.Field, ASnapshot.Columns[AMove.Column]);
  end;
end;

class function TAtlasYouTrackWorkflow.Fire(const AMove: TAtlasBoardMove;
  ATransition: Integer): TAtlasTrackerWriteResult;
var
  mWatch: TStopwatch;
  mSend: IAtlasCiSend;
  mChange: TAtlasTrackerWrite;
  mUrl: string;
  mResponse: TAtlasCiResponse;
begin
  Result := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotConfigured, 0, '');
  mUrl := FieldUrl(AMove.Target, AMove.Card.Key, AMove.Card.Workflow.FieldId);
  if (mUrl = '') or not Supports(AMove.Transport, IAtlasCiSend, mSend) then
  begin
    Exit;
  end;
  mWatch := TStopwatch.StartNew;
  Result := TAtlasTrackerWriteResult.Ok;
  if Trim(AMove.Comment) <> '' then
  begin
    mChange := TAtlasTrackerWrite.Empty;
    mChange.Comment := AMove.Comment;
    Result := TAtlasYouTrackApi.ApplyChange(AMove.Target, AMove.Transport, AMove.Card.Key, mChange, AMove.TimeoutMs);
  end;
  if not Result.Succeeded then
  begin
    Exit;
  end;
  if not mSend.Send('POST', mUrl, EventJson(AMove.Card.Workflow.FieldId,
    AMove.Card.Workflow.Transitions[ATransition]), Rest(mWatch, AMove.TimeoutMs), mResponse) then
  begin
    Result := TAtlasTrackerWriteResult.Failed(mResponse.Error, 0, '');
  end
  else if (mResponse.Status < 200) or (mResponse.Status > 299) then
  begin
    Result := TAtlasTrackerWriteResult.Failed(TAtlasYouTrackApi.ErrorOfStatus(mResponse.Status), mResponse.Status,
      TAtlasYouTrackApi.ErrorMessage(mResponse.Text));
  end;
end;

class function TAtlasYouTrackWorkflow.SetValue(const AMove: TAtlasBoardMove; const AField: string;
  const AColumn: TAtlasBoardColumn): TAtlasTrackerWriteResult;
var
  mWatch: TStopwatch;
  mChange: TAtlasTrackerWrite;
  mValue: string;
begin
  Result := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, 0, '');
  mWatch := TStopwatch.StartNew;
  for mValue in AColumn.Values do
  begin
    mChange := TAtlasTrackerWrite.Empty;
    mChange.StateField := AField;
    mChange.State := mValue;
    mChange.Comment := AMove.Comment;
    Result := TAtlasYouTrackApi.ApplyChange(AMove.Target, AMove.Transport, AMove.Card.Key, mChange,
      Rest(mWatch, AMove.TimeoutMs));
    if Result.Succeeded or (Result.Error <> TAtlasCiFetchError.Invalid) then
    begin
      Break;
    end;
  end;
end;

end.
