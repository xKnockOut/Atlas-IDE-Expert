unit Atlas.IDE.Debug.ExceptionRules;

// Exception-Regeln beim Debuggen in der IDE (#2549 nach Meldung, #838 nach
// Klasse und Ort):
// - Persönliche Regeln liegen mit der Ignorier-Liste in debug-ignore.json,
//   die des Projekts in der Projektdatei .atlas ("exceptionRules",
//   TAtlasIdeTeamFile). Persönliche gelten vor denen des Projekts; die erste passende gewinnt.
// - Regeln mit Meldung wirken mit debug.exceptionMessageRules, die übrigen
//   (und alle des Projekts ohne Meldung) mit debug.exceptionRules.
// - Treffer je Regel zählt Atlas für die laufende Sitzung (Fenster
//   „Exception-Regeln“).
// - „Nur an dieser Stelle ignorieren“ legt mit debug.exceptionRules eine
//   Regel für die erste eigene Methode an (IgnoreHere).
// - Die persönlichen Regeln liest und speichert TAtlasIdeDebugExceptions; es
//   meldet dafür beim Start seinen Speicher an (Bind), damit diese Unit es
//   nicht einbinden muss.
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.Exceptions,
  Atlas.Core.Debug.ExceptionRules;

type
  /// <summary>Speichert die persönlichen Regeln und meldet ASaid ('' = still).</summary>
  TAtlasExceptionRuleSave = reference to procedure(const ARules: TAtlasExceptionRuleList; const ASaid: string);

  /// <summary>Ablage der persönlichen Regeln (debug-ignore.json); ohne Bind leer.</summary>
  TAtlasExceptionRuleStore = record
    Read: TFunc<TAtlasExceptionRuleList>;
    Save: TAtlasExceptionRuleSave;
  end;

  TAtlasIdeExceptionRules = class
  private class var
    FHits: TAtlasExceptionRuleHits;
    FStore: TAtlasExceptionRuleStore;
    /// <summary>Zuletzt gelesener Text aus .atlas und seine Regeln (nicht bei jeder Exception neu parsen).
    /// </summary>
    FProjectText: string;
    FProject: TAtlasExceptionRuleList;
    class function Personal: TAtlasExceptionRuleList; static;
    class procedure SavePersonal(const ARules: TAtlasExceptionRuleList; const ASaid: string); static;
  public
    /// <summary>Ablage der persönlichen Regeln anmelden; Default(TAtlasExceptionRuleStore) meldet sie ab.</summary>
    class procedure Bind(const AStore: TAtlasExceptionRuleStore); static;
    /// <summary>Regeln aus der Projektdatei .atlas; ohne Datei keine.</summary>
    class function ProjectRules: TAtlasExceptionRuleList; static;
    /// <summary>Alle Regeln in der Reihenfolge, in der sie gelten.</summary>
    class function All: TAtlasExceptionRuleList; static;
    /// <summary>Erste passende Regel aus APersonal und denen des Projekts nach den Schaltern; zählt ihren Treffer.
    /// </summary>
    class function Decide(const APersonal: TAtlasExceptionRuleList; const AFacts: TAtlasExceptionFacts;
      out AAction: TAtlasExceptionAction): Boolean; static;
    /// <summary>Neue Debug-Sitzung: Treffer zurück auf 0.</summary>
    class procedure SessionStarted; static;
    /// <summary>Persönliche Regel speichern (#2549); False, wenn sie schon so galt oder unbrauchbar ist.</summary>
    class function AddRule(const ARule: TAtlasExceptionRule): Boolean; static;
    /// <summary>Persönliche Regeln mit Meldung für AClass entfernen (#2549).</summary>
    class procedure RemoveMessageRules(const AClass: string); static;
    /// <summary>„Nur an dieser Stelle ignorieren“ als Regel (#838): Klasse in der ersten eigenen Methode nur
    /// vermerken. False ohne debug.exceptionRules oder ohne eigene Methode (dann gilt der gemerkte Ort).</summary>
    class function IgnoreHere(const AClass: string; const AFrames: TAtlasDebugFrames): Boolean; static;
    /// <summary>Dialog „Regel nach Meldungstext“ (#2549) für AException; AIgnore schlägt „ignorieren“ vor, sonst
    /// „nur bei dieser Meldung anhalten“. True, wenn die neue Regel AException selbst fortsetzt.</summary>
    class function AskMessageRule(const AException: TAtlasDebugException; AIgnore: Boolean): Boolean; static;
    /// <summary>Fenster „Exception-Regeln“ zeigen.</summary>
    class procedure ShowWindow; static;
  end;

implementation

uses
  System.JSON,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.TeamFile,
  Atlas.Core.Debug.IgnoreList,
  Atlas.UI.Debug.ExceptionMessageRule,
  Atlas.UI.Debug.ExceptionRuleList,
  Atlas.UI.Debug.Exceptions.Strings;

{ TAtlasIdeExceptionRules }

class procedure TAtlasIdeExceptionRules.Bind(const AStore: TAtlasExceptionRuleStore);
begin
  FStore := AStore;
end;

class function TAtlasIdeExceptionRules.Personal: TAtlasExceptionRuleList;
begin
  Result := nil;
  if Assigned(FStore.Read) then
  begin
    Result := FStore.Read();
  end;
end;

class procedure TAtlasIdeExceptionRules.SavePersonal(const ARules: TAtlasExceptionRuleList; const ASaid: string);
begin
  if Assigned(FStore.Save) then
  begin
    FStore.Save(ARules, ASaid);
  end;
end;

class function TAtlasIdeExceptionRules.ProjectRules: TAtlasExceptionRuleList;
var
  mText: string;
  mValue: TJSONValue;
begin
  mText := TAtlasIdeTeamFile.Current.ExceptionRules;
  if mText <> FProjectText then
  begin
    FProjectText := mText;
    FProject := nil;
    mValue := nil;
    if mText <> '' then
    begin
      mValue := TJSONObject.ParseJSONValue(mText);
    end;
    try
      FProject := TAtlasExceptionRules.Parse(mValue);
    finally
      mValue.Free;
    end;
  end;
  Result := FProject;
end;

class function TAtlasIdeExceptionRules.All: TAtlasExceptionRuleList;
begin
  Result := TAtlasExceptionRules.Combined(Personal, ProjectRules);
end;

class function TAtlasIdeExceptionRules.Decide(const APersonal: TAtlasExceptionRuleList;
  const AFacts: TAtlasExceptionFacts; out AAction: TAtlasExceptionAction): Boolean;
var
  mAll: TAtlasExceptionRuleList;
  mIndex: Integer;
begin
  AAction := TAtlasExceptionAction.Stop;
  mAll := TAtlasExceptionRules.Combined(APersonal, nil);
  if TAtlasIdeSettings.Current.DebugExceptionRules then
  begin
    mAll := TAtlasExceptionRules.Combined(APersonal, ProjectRules);
  end;
  mIndex := TAtlasExceptionRules.FirstMatch(mAll, AFacts, TAtlasExceptionRules.Kinds(
    TAtlasIdeSettings.Current.DebugExceptionMessageRules, TAtlasIdeSettings.Current.DebugExceptionRules));
  Result := mIndex >= 0;
  if Result then
  begin
    AAction := mAll[mIndex].Action;
    FHits.Add(mAll[mIndex].Key);
  end;
end;

class procedure TAtlasIdeExceptionRules.SessionStarted;
begin
  FHits.Clear;
end;

class function TAtlasIdeExceptionRules.AddRule(const ARule: TAtlasExceptionRule): Boolean;
var
  mRules: TAtlasExceptionRuleList;
begin
  mRules := Personal;
  Result := TAtlasExceptionRules.Put(mRules, ARule);
  if not Result then
  begin
    Exit;
  end;
  if ARule.HasMessage then
  begin
    SavePersonal(mRules, TAtlasExceptionsStrings.Fmt(TAtlasExceptionsTextId.DebugMessageRuleSaid,
      [ARule.ExceptionClass, ARule.Message]));
  end
  else
  begin
    SavePersonal(mRules, TAtlasExceptionsStrings.Fmt(TAtlasExceptionsTextId.DebugRulePlaceSaid,
      [ARule.ExceptionClass, ARule.Location]));
  end;
end;

class procedure TAtlasIdeExceptionRules.RemoveMessageRules(const AClass: string);
var
  mList: TAtlasDebugIgnoreList;
begin
  mList := TAtlasDebugIgnoreList.Empty;
  mList.Rules := Personal;
  if mList.RemoveMessageRules(AClass) > 0 then
  begin
    SavePersonal(mList.Rules,
      TAtlasExceptionsStrings.Fmt(TAtlasExceptionsTextId.DebugMessageRulesRemovedSaid, [AClass]));
  end;
end;

class function TAtlasIdeExceptionRules.IgnoreHere(const AClass: string; const AFrames: TAtlasDebugFrames): Boolean;
var
  mRule: TAtlasExceptionRule;
  mMethod: string;
begin
  mMethod := TAtlasExceptionRules.OwnRoutine(AFrames);
  Result := TAtlasIdeSettings.Current.DebugExceptionRules and (mMethod <> '') and (Trim(AClass) <> '');
  if not Result then
  begin
    Exit;
  end;
  mRule := TAtlasExceptionRule.Create(AClass, '', TAtlasMessageMatch.Matches, TAtlasExceptionAction.Log);
  mRule.Location := mMethod;
  // Schon so vorhanden zählt auch: Die Stelle ist dann ebenfalls ignoriert.
  AddRule(mRule);
end;

class function TAtlasIdeExceptionRules.AskMessageRule(const AException: TAtlasDebugException;
  AIgnore: Boolean): Boolean;
var
  mMode: TAtlasMessageRuleMode;
  mRule: TAtlasExceptionRule;
begin
  mMode := TAtlasMessageRuleMode.StopOnly;
  if AIgnore then
  begin
    mMode := TAtlasMessageRuleMode.Ignore;
  end;
  Result := TAtlasExceptionMessageRuleDialog.Execute(TAtlasMessageRuleInput.Create(AException.ExceptionClass,
    AException.Message, TAtlasExceptionRules.OwnUnit(AException.Frames), mMode), mRule) and AddRule(mRule) and
    mRule.Matches(TAtlasExceptionFacts.Create(AException.ExceptionClass, AException.Message,
    TAtlasExceptionRules.OwnRoutine(AException.Frames)));
end;

class procedure TAtlasIdeExceptionRules.ShowWindow;
var
  mPersonal: TAtlasExceptionRuleList;
begin
  if TAtlasExceptionRuleListDialog.Execute(All, FHits,
    procedure
    begin
      TAtlasIdeTeamFile.OpenInEditor;
    end, mPersonal) then
  begin
    SavePersonal(mPersonal, TAtlasExceptionsStrings.Fmt(TAtlasExceptionsTextId.DebugRulesSaid,
      [Length(mPersonal)]));
  end;
end;

end.
