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
// - Regeln „mit Nachfahren“: Die Vorfahren der Klasse fragt Atlas beim Server
//   (workspace/symbol, dann typeHierarchy/supertypes), nur wenn eine solche
//   Regel sie braucht, und merkt sie je Klasse bis zur nächsten Debug-Sitzung.
//   Ohne Server oder ohne die Klasse im Index passt nur die Klasse selbst.
// - Im Fenster geänderte Regeln des Projekts schreibt Atlas in die .atlas
//   (TAtlasIdeTeamFile.TargetFile); Kommentare und übrige Schlüssel bleiben.
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
    /// <summary>Gefragte Klassen und ihre Vorfahren (je Sitzung).</summary>
    FAncestorClasses: TArray<string>;
    FAncestorLists: TArray<TArray<string>>;
    class function Personal: TAtlasExceptionRuleList; static;
    class procedure SavePersonal(const ARules: TAtlasExceptionRuleList; const ASaid: string); static;
    /// <summary>Vorfahren von AClass, nächster zuerst; aus dem Zwischenspeicher oder vom Server.</summary>
    class function AncestorsOf(const AClass: string): TArray<string>; static;
    /// <summary>Regeln des Projekts in die .atlas schreiben (Meldung über SavePersonal-Weg).</summary>
    class procedure SaveProject(const ARules: TAtlasExceptionRuleList); static;
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
  System.Generics.Collections,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Files.Contract,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Settings.TeamFile,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.TeamFile,
  Atlas.Core.Debug.IgnoreList,
  Atlas.UI.Debug.ExceptionMessageRule,
  Atlas.UI.Debug.ExceptionRuleList,
  Atlas.UI.Debug.Exceptions.Strings;

const
  /// <summary>LSP SymbolKind Class.</summary>
  cSymbolClass = 5;
  cSymbolTimeoutMs = 1000;
  cMaxAncestors = 16;

/// <summary>Erster Eintrag, der eine Klasse ist; False ohne.</summary>
function FirstClass(const AItems: TArray<TAtlasHierarchyItem>; out AItem: TAtlasHierarchyItem): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AItems) do
  begin
    if AItems[mIndex].Kind = cSymbolClass then
    begin
      AItem := AItems[mIndex];
      Exit(True);
    end;
  end;
  AItem := Default(TAtlasHierarchyItem);
  Result := False;
end;

/// <summary>Deklaration der Klasse AClass im Index; False ohne.</summary>
function FindClass(ASession: TLspSession; const AClass: string; out ASymbol: TAtlasSymbol): Boolean;
var
  mSymbols: TArray<TAtlasSymbol>;
  mIndex: Integer;
begin
  mSymbols := ASession.WorkspaceSymbols(AClass, cSymbolTimeoutMs);
  for mIndex := 0 to High(mSymbols) do
  begin
    if (mSymbols[mIndex].Kind = cSymbolClass) and SameText(mSymbols[mIndex].Name, AClass) then
    begin
      ASymbol := mSymbols[mIndex];
      Exit(True);
    end;
  end;
  ASymbol := Default(TAtlasSymbol);
  Result := False;
end;

/// <summary>Vorfahren von AClass laut Server, nächster zuerst; nil ohne Server oder Klasse.</summary>
function QueryAncestors(const AClass: string): TArray<string>;
var
  mSession: TLspSession;
  mSymbol: TAtlasSymbol;
  mItem: TAtlasHierarchyItem;
begin
  Result := nil;
  mSession := TAtlasIdeHost.RunningSession;
  if (mSession = nil) or not FindClass(mSession, AClass, mSymbol) or
    not FirstClass(mSession.PrepareHierarchy(TAtlasHierarchyDirection.Supertypes, mSymbol.FileName, mSymbol.Line,
    mSymbol.Character), mItem) then
  begin
    Exit;
  end;
  while (Length(Result) < cMaxAncestors) and
    FirstClass(mSession.HierarchyChildren(TAtlasHierarchyDirection.Supertypes, mItem), mItem) do
  begin
    Result := Result + [mItem.Name];
  end;
end;

{ TAtlasIdeExceptionRules }

class function TAtlasIdeExceptionRules.AncestorsOf(const AClass: string): TArray<string>;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FAncestorClasses) do
  begin
    if SameText(FAncestorClasses[mIndex], AClass) then
    begin
      Exit(Copy(FAncestorLists[mIndex]));
    end;
  end;
  Result := QueryAncestors(AClass);
  FAncestorClasses := FAncestorClasses + [AClass];
  SetLength(FAncestorLists, Length(FAncestorLists) + 1);
  FAncestorLists[High(FAncestorLists)] := Copy(Result);
end;

class procedure TAtlasIdeExceptionRules.SaveProject(const ARules: TAtlasExceptionRuleList);
var
  mFileName: string;
  mContent: TAtlasTextFileContent;
begin
  mFileName := TAtlasIdeTeamFile.TargetFile;
  if not (TAtlasIdeSettings.Current.Enabled and TAtlasIdeSettings.Current.TeamFile) or (mFileName = '') then
  begin
    SavePersonal(Personal, TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugRulesProjectOff));
    Exit;
  end;
  try
    mContent := Default(TAtlasTextFileContent);
    mContent.Encoding := TAtlasTextEncoding.Utf8;
    if FileExists(mFileName) then
    begin
      mContent := TAtlasTextFile.Load(mFileName);
    end;
    mContent.Text := TAtlasExceptionRules.WithProjectRules(mContent.Text, TAtlasTeamFile.Skeleton, ARules);
    TAtlasTextFile.Save(mFileName, mContent);
  except
    on E: Exception do
    begin
      SavePersonal(Personal, TAtlasExceptionsStrings.Fmt(TAtlasExceptionsTextId.DebugRulesProjectFailed,
        [E.Message]));
      Exit;
    end;
  end;
  TAtlasIdeTeamFile.Refresh;
  SavePersonal(Personal, TAtlasExceptionsStrings.Fmt(TAtlasExceptionsTextId.DebugRulesProjectSaved,
    [mFileName, Length(ARules)]));
end;

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
  mKinds: TAtlasExceptionRuleKinds;
  mFacts: TAtlasExceptionFacts;
begin
  AAction := TAtlasExceptionAction.Stop;
  mAll := TAtlasExceptionRules.Combined(APersonal, nil);
  if TAtlasIdeSettings.Current.DebugExceptionRules then
  begin
    mAll := TAtlasExceptionRules.Combined(APersonal, ProjectRules);
  end;
  mKinds := TAtlasExceptionRules.Kinds(TAtlasIdeSettings.Current.DebugExceptionMessageRules,
    TAtlasIdeSettings.Current.DebugExceptionRules);
  mFacts := AFacts;
  if TAtlasExceptionRules.NeedsAncestors(mAll, AFacts.ExceptionClass, mKinds) then
  begin
    mFacts.Ancestors := AncestorsOf(AFacts.ExceptionClass);
  end;
  mIndex := TAtlasExceptionRules.FirstMatch(mAll, mFacts, mKinds);
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
  // Klassen können sich seit der letzten Sitzung geändert haben.
  FAncestorClasses := nil;
  FAncestorLists := nil;
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
  mPersonal, mProject, mOld: TAtlasExceptionRuleList;
begin
  mOld := ProjectRules;
  if TAtlasExceptionRuleListDialog.Execute(All, FHits,
    procedure
    begin
      TAtlasIdeTeamFile.OpenInEditor;
    end, mPersonal, mProject) then
  begin
    // Zuerst die persönlichen Regeln: SaveProject meldet über denselben Weg und liest sie neu.
    SavePersonal(mPersonal, TAtlasExceptionsStrings.Fmt(TAtlasExceptionsTextId.DebugRulesSaid,
      [Length(mPersonal)]));
    if not TAtlasExceptionRules.SameRules(mOld, mProject) then
    begin
      SaveProject(mProject);
    end;
  end;
end;

end.
