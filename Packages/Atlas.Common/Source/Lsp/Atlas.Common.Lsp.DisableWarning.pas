unit Atlas.Common.Lsp.DisableWarning;

// „Warnung hier abschalten“ über das Protokoll (#531):
//   - Code-Aktionen auf Zeilen mit einer Warnung oder einem Hinweis des
//     letzten Compilerlaufs (atlas/compilerMessages, #528), nur mit
//     refactoring.disableWarning: „hier“ (um die Zeile), „in Routine“, „in der
//     ganzen Unit“. Ablaufmeldungen (H2164, W1035 …) gibt es nicht um die
//     Zeile, dort ist die Routine die bevorzugte Aktion. Alle tragen den
//     Client-Befehl atlas.disableWarning [uri, Zeile, Nummer, Bereich, fragen];
//     das Plugin fragt die Begründung nach (refactoring.disableWarningReason).
//   - Für Warnungen mit eigenem Bezeichner dazu „im ganzen Projekt“: Client-
//     Befehl atlas.disableWarningProject [uri, Nummer, Bezeichner]; das Plugin
//     fragt nach und trägt den Bezeichner in die Projektoptionen ein.
//   - Befehl atlas.server.disableWarning [uri, Zeile, Nummer, Bereich,
//     Begründung]: WorkspaceEdit mit den Schaltern ({"edit", "allWarnings"}).
// Den Text erzeugt Atlas.Common.Editing.DisableWarning.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.DisableWarning;

type
  TDisableWarningOptions = record
    /// <summary>refactoring.disableWarning.</summary>
    Enabled: Boolean;
    /// <summary>refactoring.disableWarningReason: Das Plugin fragt nach einer Begründung.</summary>
    AskReason: Boolean;
    /// <summary>Delphi-Version des Projekts (BDS-Nummer); leer = aktuelle.</summary>
    Version: string;
  end;

  TLspDisableWarning = class
  public const
    cClientCommand = 'atlas.disableWarning';
    cProjectCommand = 'atlas.disableWarningProject';
    cApplyCommand = 'atlas.server.disableWarning';
    cKind = 'quickfix';
  public
    /// <summary>Name des Bereichs im Befehl: line, routine, unit.</summary>
    class function ScopeName(AScope: TDisableWarningScope): string; static;
    class function TryParseScope(const AName: string; out AScope: TDisableWarningScope): Boolean; static;
    /// <summary>Code-Aktionen für die Meldungen AMessages (Zeilen ab 0) auf den Zeilen AFirstLine..ALastLine.
    /// </summary>
    class function Actions(const AOptions: TDisableWarningOptions; ATree: TSyntaxTree; const AUri: string;
      AFirstLine, ALastLine: Integer; const AMessages: TArray<TCompilerMessage>): TArray<TJSONObject>; static;
    /// <summary>atlas.server.disableWarning für den Text AText (Baum ATree) der Datei AUri.</summary>
    class function Execute(const AArguments: TJSONArray; const AText: string; ATree: TSyntaxTree;
      const AVersion: string): TJSONValue; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TDisableWarningText = (SwitchOffInTheWhole, ArgumentsUriLineCodeAnd, IsNeitherAWarningNor, ThereIsNoMatchingRange,
    AffectsAllWarnings, SwitchOffInTheWhole2, SwitchOffHere, SwitchOffIn, UnknownScope);

const
  cTexts: array[TDisableWarningText] of TAtlasText = (
    (De: '%s in der ganzen Unit abschalten (%s)'; En: 'Switch off %s in the whole unit (%s)'),
    (De: 'Argumente "uri", "line", "code" und "scope" fehlen';
     En: 'Arguments "uri", "line", "code" and "scope" missing'),
    (De: ' ist keine Warnung und kein Hinweis.'; En: ' is neither a warning nor a hint.'),
    (De: 'An dieser Stelle gibt es keinen passenden Bereich (Zeile, Routine oder Unit-Kopf).';
     En: 'There is no matching range at this position (line, routine or unit header).'),
    (De: ': betrifft alle Warnungen'; En: ': affects all warnings'),
    (De: '%s im ganzen Projekt abschalten (Projektoptionen)';
     En: 'Switch off %s in the whole project (project options)'),
    (De: '%s hier abschalten (%s)'; En: 'Switch off %s here (%s)'),
    (De: '%s in %s abschalten (%s)'; En: 'Switch off %s in %s (%s)'),
    (De: 'Unbekannter Bereich: '; En: 'Unknown scope: '));

{$SCOPEDENUMS OFF}

const
  cScopeNames: array[TDisableWarningScope] of string = ('line', 'routine', 'unit');

class function TLspDisableWarning.ScopeName(AScope: TDisableWarningScope): string;
begin
  Result := cScopeNames[AScope];
end;

class function TLspDisableWarning.TryParseScope(const AName: string; out AScope: TDisableWarningScope): Boolean;
var
  mScope: TDisableWarningScope;
begin
  for mScope := Low(TDisableWarningScope) to High(TDisableWarningScope) do
  begin
    if SameText(cScopeNames[mScope], AName) then
    begin
      AScope := mScope;
      Exit(True);
    end;
  end;
  AScope := TDisableWarningScope.Line;
  Result := False;
end;

function SwitchHint(const ASwitch: TDisableWarningSwitch): string;
begin
  Result := ASwitch.OffText;
  if ASwitch.AllWarnings then
  begin
    Result := Result + cTexts[TDisableWarningText.AffectsAllWarnings].Text;
  end;
end;

function CommandAction(const ATitle, ACommand: string; AArguments: TJSONArray; APreferred: Boolean): TJSONObject;
var
  mCommand: TJSONObject;
begin
  mCommand := TJSONObject.Create;
  mCommand.AddPair('title', ATitle);
  mCommand.AddPair('command', ACommand);
  mCommand.AddPair('arguments', AArguments);
  Result := TJSONObject.Create;
  Result.AddPair('title', ATitle);
  Result.AddPair('kind', TLspDisableWarning.cKind);
  if APreferred then
  begin
    Result.AddPair('isPreferred', TJSONBool.Create(True));
  end;
  Result.AddPair('command', mCommand);
end;

type
  /// <summary>Meldung, zu der eine Aktion entsteht: Datei, Zeile (ab 0) und Schalter.</summary>
  TWarningSpot = record
    Uri: string;
    Line: Integer;
    Switch: TDisableWarningSwitch;
  end;

function ScopeAction(const AOptions: TDisableWarningOptions; const ASpot: TWarningSpot;
  AScope: TDisableWarningScope; const ATitle: string; APreferred: Boolean): TJSONObject;
var
  mArguments: TJSONArray;
begin
  mArguments := TJSONArray.Create;
  mArguments.Add(ASpot.Uri);
  mArguments.AddElement(TJSONNumber.Create(ASpot.Line));
  mArguments.Add(ASpot.Switch.Code);
  mArguments.Add(TLspDisableWarning.ScopeName(AScope));
  mArguments.AddElement(TJSONBool.Create(AOptions.AskReason));
  Result := CommandAction(ATitle, TLspDisableWarning.cClientCommand, mArguments, APreferred);
end;

function SpotOf(const AUri: string; ALine: Integer; const ASwitch: TDisableWarningSwitch): TWarningSpot;
begin
  Result.Uri := AUri;
  Result.Line := ALine;
  Result.Switch := ASwitch;
end;

/// <summary>„im ganzen Projekt abschalten“ für Warnungen mit eigenem Bezeichner.</summary>
function ProjectAction(const ASpot: TWarningSpot): TJSONObject;
var
  mArguments: TJSONArray;
begin
  mArguments := TJSONArray.Create;
  mArguments.Add(ASpot.Uri);
  mArguments.Add(ASpot.Switch.Code);
  mArguments.Add(ASpot.Switch.Identifier);
  Result := CommandAction(cTexts[TDisableWarningText.SwitchOffInTheWhole2].Fmt([ASpot.Switch.Code]),
    TLspDisableWarning.cProjectCommand, mArguments, False);
end;

class function TLspDisableWarning.Actions(const AOptions: TDisableWarningOptions; ATree: TSyntaxTree;
  const AUri: string; AFirstLine, ALastLine: Integer; const AMessages: TArray<TCompilerMessage>):
  TArray<TJSONObject>;
var
  mSeen: TDictionary<string, Boolean>;
  mMessage: TCompilerMessage;
  mSwitch: TDisableWarningSwitch;
  mRoutine: TSyntaxNode;
  mHasHeader: Boolean;
  mSpot: TWarningSpot;
begin
  Result := nil;
  if not AOptions.Enabled or (ATree = nil) then
  begin
    Exit;
  end;
  mHasHeader := TDisableWarning.HeaderEndLine(ATree) >= 0;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    for mMessage in AMessages do
    begin
      if (mMessage.Line < AFirstLine) or (mMessage.Line > ALastLine) or
        not TDisableWarning.SwitchFor(mMessage.Code, AOptions.Version, mSwitch) or
        mSeen.ContainsKey(mSwitch.Code + '@' + IntToStr(mMessage.Line)) then
      begin
        Continue;
      end;
      mSeen.Add(mSwitch.Code + '@' + IntToStr(mMessage.Line), True);
      mSpot := SpotOf(AUri, mMessage.Line, mSwitch);
      // Ablaufmeldungen prüft der Compiler am Ende der Routine: Ein Schalter um die Zeile wirkte nicht.
      if not mSwitch.RoutineWide then
      begin
        Result := Result + [ScopeAction(AOptions, mSpot, TDisableWarningScope.Line,
          cTexts[TDisableWarningText.SwitchOffHere].Fmt([mSwitch.Code, SwitchHint(mSwitch)]), True)];
      end;
      mRoutine := TDisableWarning.RoutineAt(ATree, mMessage.Line);
      if mRoutine <> nil then
      begin
        Result := Result + [ScopeAction(AOptions, mSpot, TDisableWarningScope.Routine,
          cTexts[TDisableWarningText.SwitchOffIn].Fmt([mSwitch.Code, mRoutine.Name, SwitchHint(mSwitch)]),
          mSwitch.RoutineWide)];
      end;
      if mHasHeader then
      begin
        Result := Result + [ScopeAction(AOptions, mSpot, TDisableWarningScope.UnitWide,
          cTexts[TDisableWarningText.SwitchOffInTheWhole].Fmt([mSwitch.Code, SwitchHint(mSwitch)]),
          mSwitch.RoutineWide and (mRoutine = nil))];
      end;
      if mSwitch.Identifier <> '' then
      begin
        Result := Result + [ProjectAction(mSpot)];
      end;
    end;
  finally
    mSeen.Free;
  end;
end;

/// <summary>WorkspaceEdit mit den Änderungen AEdits an der Datei AUri.</summary>
function WorkspaceEditJson(const AUri: string; const AEdits: TArray<TTextEdit>): TJSONObject;
var
  mEdit: TTextEdit;
  mDocument, mTextDocument, mItem: TJSONObject;
  mItems, mChanges: TJSONArray;
begin
  mItems := TJSONArray.Create;
  for mEdit in AEdits do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('range', TLspPositions.RangeToJson(mEdit.Range));
    mItem.AddPair('newText', mEdit.NewText);
    mItems.AddElement(mItem);
  end;
  mTextDocument := TJSONObject.Create;
  mTextDocument.AddPair('uri', AUri);
  mTextDocument.AddPair('version', TJSONNull.Create);
  mDocument := TJSONObject.Create;
  mDocument.AddPair('textDocument', mTextDocument);
  mDocument.AddPair('edits', mItems);
  mChanges := TJSONArray.Create;
  mChanges.AddElement(mDocument);
  Result := TJSONObject.Create;
  Result.AddPair('documentChanges', mChanges);
end;

/// <summary>Begründung aus dem fünften Argument; leer, wenn es fehlt.</summary>
function ReasonArgument(const AArguments: TJSONArray): string;
begin
  Result := '';
  if AArguments.Count > 4 then
  begin
    Result := AArguments.Items[4].Value;
  end;
end;

class function TLspDisableWarning.Execute(const AArguments: TJSONArray; const AText: string; ATree: TSyntaxTree;
  const AVersion: string): TJSONValue;
var
  mScope: TDisableWarningScope;
  mSwitch: TDisableWarningSwitch;
  mEdits: TArray<TTextEdit>;
  mAnswer: TJSONObject;
begin
  if (AArguments = nil) or (AArguments.Count < 4) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TDisableWarningText.ArgumentsUriLineCodeAnd].Text);
  end;
  if not TryParseScope(AArguments.Items[3].Value, mScope) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TDisableWarningText.UnknownScope].Text +
      AArguments.Items[3].Value);
  end;
  if not TDisableWarning.SwitchFor(AArguments.Items[2].Value, AVersion, mSwitch) then
  begin
    raise EJsonRpcError.Create(TLspErrorCode.cRequestFailed,
      AArguments.Items[2].Value + cTexts[TDisableWarningText.IsNeitherAWarningNor].Text);
  end;
  if not TDisableWarning.Edits(AText, ATree, StrToIntDef(AArguments.Items[1].Value, -1),
    TDisableWarningRequest.Create(mSwitch, mScope, ReasonArgument(AArguments)), mEdits) then
  begin
    raise EJsonRpcError.Create(TLspErrorCode.cRequestFailed,
      cTexts[TDisableWarningText.ThereIsNoMatchingRange].Text);
  end;
  mAnswer := TJSONObject.Create;
  mAnswer.AddPair('edit', WorkspaceEditJson(AArguments.Items[0].Value, mEdits));
  mAnswer.AddPair('allWarnings', TJSONBool.Create(mSwitch.AllWarnings));
  Result := mAnswer;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.DisableWarning', cTexts);

end.
