unit Atlas.Core.Tracker.YouTrackWorkflow;

// Karten im Board von YouTrack verschieben (#1272) und Regeln des
// Zustandsfeldes eines Issues lesen (#2122), ohne VCL und Open Tools API,
// unter Beachtung der Workflow-Regeln. Steuert eine Zustandsmaschine
// das Spaltenfeld ("StateMachineIssueCustomField"), lässt YouTrack ab dem
// aktuellen Wert nur bestimmte Übergänge zu ("possibleEvents"); ein Wert ohne
// Übergang wird abgelehnt ("No event found"). Das Board von YouTrack löst
// deshalb den passenden Übergang aus, statt den Wert zu setzen. Atlas macht
// es genauso:
// - Lesen: die Felder einer Karte bringen $type, id und possibleEvents(id,
//   presentation) mit (CardFieldParts in TAtlasYouTrackBoards.cCardFields),
//   beim Beginnen und Beenden das Issue selbst
//   (TAtlasYouTrackApi.cStateRuleFields, mit dem aktuellen Wert).
// - Auslösen: POST <url>/api/issues/<Kennung>/fields/<Feld-ID> mit
//   {"event": {"id": …, "presentation": …, "$type": "Event"}, "id": …,
//   "$type": "StateMachineIssueCustomField"} (TAtlasYouTrackApi.ApplyChange
//   mit TAtlasTrackerWrite.Transition); ein Kommentar geht vorher als
//   eigener Kommentar hinaus, damit bei einem Fehler nichts halb geändert ist.
// - Ohne passenden Übergang (oder ohne Zustandsmaschine) ein Befehl je Wert
//   der Zielspalte: Lehnt YouTrack einen Wert ab (400, etwa weil eine Regel
//   nur einen anderen Wert einer zusammengefassten Spalte erlaubt), folgt der
//   nächste; bei anderen Fehlern nicht.
// Welcher Übergang in welche Spalte führt, entscheidet TAtlasBoardTransitions
// (Atlas.Core.Tracker.Board, über Atlas.Core.Tracker.Transitions); Befehle,
// Status und Fehlertexte über TAtlasYouTrackApi.

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
    /// <summary>Felder, die eine Karte zusätzlich zu name und value je Feld braucht.</summary>
    cCardFieldParts = 'id,possibleEvents(id,presentation)';
  public
    /// <summary>Regeln des Feldes AField aus customFields von AIssue (ohne Groß-/Kleinschreibung). Ohne
    /// Zustandsmaschine oder ohne possibleEvents in der Antwort ist StateMachine False (dann entscheidet YouTrack
    /// beim Verschieben); Current trägt den Wert, falls die Antwort ihn enthält.</summary>
    class function Find(AIssue: TJSONObject; const AField: string): TAtlasTrackerStateRules; static;
    /// <summary>Regeln eines einzelnen Feldes aus customFields.</summary>
    class function Parse(AField: TJSONObject): TAtlasTrackerStateRules; static;
    /// <summary>Regeln des Feldes AField aus der Antwort auf GET /api/issues/&lt;Kennung&gt;?fields=
    /// TAtlasYouTrackApi.cStateRuleFields; False bei ungültigem JSON.</summary>
    class function ParseIssue(const AJson, AField: string; out ARules: TAtlasTrackerStateRules): Boolean; static;
    /// <summary>Regeln des Zustandsfeldes AField am Issue AKey lesen (#2122).</summary>
    class function Read(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey,
      AField: string; ATimeoutMs: Integer; out ARules: TAtlasTrackerStateRules): TAtlasTrackerWriteResult; static;
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
  Atlas.Core.Tracker.YouTrackApi,
  Atlas.Text.Json;

{ TAtlasYouTrackWorkflow }

class function TAtlasYouTrackWorkflow.Parse(AField: TJSONObject): TAtlasTrackerStateRules;
var
  mEvents, mItem, mValue: TJSONValue;
  mId: string;
begin
  Result := Default(TAtlasTrackerStateRules);
  mValue := AField.Values['value'];
  if mValue is TJSONObject then
  begin
    Result.Current := Trim(TJsonRead.Text(TJSONObject(mValue), 'name'));
  end;
  mEvents := AField.Values['possibleEvents'];
  if not SameText(TJsonRead.Text(AField, '$type'), TAtlasYouTrackApi.cStateMachineType) or
    not (mEvents is TJSONArray) then
  begin
    Exit;
  end;
  Result.StateMachine := True;
  Result.FieldId := TJsonRead.Text(AField, 'id');
  for mItem in TJSONArray(mEvents) do
  begin
    if mItem is TJSONObject then
    begin
      mId := TJsonRead.Text(TJSONObject(mItem), 'id');
      if mId <> '' then
      begin
        Result.Transitions := Result.Transitions +
          [TAtlasTrackerTransition.Create(mId, TJsonRead.Text(TJSONObject(mItem), 'presentation'))];
      end;
    end;
  end;
end;

class function TAtlasYouTrackWorkflow.Find(AIssue: TJSONObject; const AField: string): TAtlasTrackerStateRules;
var
  mFields, mItem: TJSONValue;
begin
  Result := Default(TAtlasTrackerStateRules);
  mFields := AIssue.Values['customFields'];
  if (AField = '') or not (mFields is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(mFields) do
  begin
    if (mItem is TJSONObject) and SameText(Trim(TJsonRead.Text(TJSONObject(mItem), 'name')), AField) then
    begin
      Exit(Parse(TJSONObject(mItem)));
    end;
  end;
end;

class function TAtlasYouTrackWorkflow.ParseIssue(const AJson, AField: string;
  out ARules: TAtlasTrackerStateRules): Boolean;
var
  mValue: TJSONValue;
begin
  ARules := Default(TAtlasTrackerStateRules);
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := mValue is TJSONObject;
    if Result then
    begin
      ARules := Find(TJSONObject(mValue), Trim(AField));
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasYouTrackWorkflow.Read(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey, AField: string; ATimeoutMs: Integer; out ARules: TAtlasTrackerStateRules): TAtlasTrackerWriteResult;
var
  mJson: string;
  mError: TAtlasCiFetchError;
begin
  ARules := Default(TAtlasTrackerStateRules);
  if ATransport = nil then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotConfigured, 0, ''));
  end;
  if not TAtlasYouTrackApi.GetText(ATransport, TAtlasYouTrackApi.IssueUrl(ATarget, AKey,
    TAtlasYouTrackApi.cStateRuleFields), ATimeoutMs, mJson, mError) then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(mError, 0, ''));
  end;
  if not ParseIssue(mJson, AField, ARules) then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, 0, ''));
  end;
  Result := TAtlasTrackerWriteResult.Ok;
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
  mChange: TAtlasTrackerWrite;
begin
  mChange := TAtlasTrackerWrite.Empty;
  mChange.Comment := AMove.Comment;
  mChange.Transition := AMove.Card.Workflow.Transitions[ATransition];
  mChange.FieldId := AMove.Card.Workflow.FieldId;
  Result := TAtlasYouTrackApi.ApplyChange(AMove.Target, AMove.Transport, AMove.Card.Key, mChange, AMove.TimeoutMs);
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
      TAtlasYouTrackApi.Rest(mWatch, AMove.TimeoutMs));
    if Result.Succeeded or (Result.Error <> TAtlasCiFetchError.Invalid) then
    begin
      Break;
    end;
  end;
end;

end.
