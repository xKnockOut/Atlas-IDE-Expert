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
    ClientCommand = 'atlas.disableWarning';
    ProjectCommand = 'atlas.disableWarningProject';
    ApplyCommand = 'atlas.server.disableWarning';
    Kind = 'quickfix';
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
  Atlas.Common.Lsp.Positions;

const
  ScopeNames: array[TDisableWarningScope] of string = ('line', 'routine', 'unit');

class function TLspDisableWarning.ScopeName(AScope: TDisableWarningScope): string;
begin
  Result := ScopeNames[AScope];
end;

class function TLspDisableWarning.TryParseScope(const AName: string; out AScope: TDisableWarningScope): Boolean;
var
  Scope: TDisableWarningScope;
begin
  for Scope := Low(TDisableWarningScope) to High(TDisableWarningScope) do
  begin
    if SameText(ScopeNames[Scope], AName) then
    begin
      AScope := Scope;
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
    Result := Result + ': betrifft alle Warnungen';
  end;
end;

function CommandAction(const ATitle, ACommand: string; AArguments: TJSONArray; APreferred: Boolean): TJSONObject;
var
  Command: TJSONObject;
begin
  Command := TJSONObject.Create;
  Command.AddPair('title', ATitle);
  Command.AddPair('command', ACommand);
  Command.AddPair('arguments', AArguments);
  Result := TJSONObject.Create;
  Result.AddPair('title', ATitle);
  Result.AddPair('kind', TLspDisableWarning.Kind);
  if APreferred then
  begin
    Result.AddPair('isPreferred', TJSONBool.Create(True));
  end;
  Result.AddPair('command', Command);
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
  Result := CommandAction(ATitle, TLspDisableWarning.ClientCommand, mArguments, APreferred);
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
  Result := CommandAction(Format('%s im ganzen Projekt abschalten (Projektoptionen)', [ASpot.Switch.Code]),
    TLspDisableWarning.ProjectCommand, mArguments, False);
end;

class function TLspDisableWarning.Actions(const AOptions: TDisableWarningOptions; ATree: TSyntaxTree;
  const AUri: string; AFirstLine, ALastLine: Integer; const AMessages: TArray<TCompilerMessage>):
  TArray<TJSONObject>;
var
  Seen: TDictionary<string, Boolean>;
  Message: TCompilerMessage;
  Switch: TDisableWarningSwitch;
  Routine: TSyntaxNode;
  HasHeader: Boolean;
  mSpot: TWarningSpot;
begin
  Result := nil;
  if not AOptions.Enabled or (ATree = nil) then
  begin
    Exit;
  end;
  HasHeader := TDisableWarning.HeaderEndLine(ATree) >= 0;
  Seen := TDictionary<string, Boolean>.Create;
  try
    for Message in AMessages do
    begin
      if (Message.Line < AFirstLine) or (Message.Line > ALastLine) or
        not TDisableWarning.SwitchFor(Message.Code, AOptions.Version, Switch) or
        Seen.ContainsKey(Switch.Code + '@' + IntToStr(Message.Line)) then
      begin
        Continue;
      end;
      Seen.Add(Switch.Code + '@' + IntToStr(Message.Line), True);
      mSpot := SpotOf(AUri, Message.Line, Switch);
      // Ablaufmeldungen prüft der Compiler am Ende der Routine: Ein Schalter um die Zeile wirkte nicht.
      if not Switch.RoutineWide then
      begin
        Result := Result + [ScopeAction(AOptions, mSpot, TDisableWarningScope.Line,
          Format('%s hier abschalten (%s)', [Switch.Code, SwitchHint(Switch)]), True)];
      end;
      Routine := TDisableWarning.RoutineAt(ATree, Message.Line);
      if Routine <> nil then
      begin
        Result := Result + [ScopeAction(AOptions, mSpot, TDisableWarningScope.Routine,
          Format('%s in %s abschalten (%s)', [Switch.Code, Routine.Name, SwitchHint(Switch)]),
          Switch.RoutineWide)];
      end;
      if HasHeader then
      begin
        Result := Result + [ScopeAction(AOptions, mSpot, TDisableWarningScope.UnitWide,
          Format('%s in der ganzen Unit abschalten (%s)', [Switch.Code, SwitchHint(Switch)]),
          Switch.RoutineWide and (Routine = nil))];
      end;
      if Switch.Identifier <> '' then
      begin
        Result := Result + [ProjectAction(mSpot)];
      end;
    end;
  finally
    Seen.Free;
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
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Argumente "uri", "line", "code" und "scope" fehlen');
  end;
  if not TryParseScope(AArguments.Items[3].Value, mScope) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Unbekannter Bereich: ' + AArguments.Items[3].Value);
  end;
  if not TDisableWarning.SwitchFor(AArguments.Items[2].Value, AVersion, mSwitch) then
  begin
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed,
      AArguments.Items[2].Value + ' ist keine Warnung und kein Hinweis.');
  end;
  if not TDisableWarning.Edits(AText, ATree, StrToIntDef(AArguments.Items[1].Value, -1),
    TDisableWarningRequest.Create(mSwitch, mScope, ReasonArgument(AArguments)), mEdits) then
  begin
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed,
      'An dieser Stelle gibt es keinen passenden Bereich (Zeile, Routine oder Unit-Kopf).');
  end;
  mAnswer := TJSONObject.Create;
  mAnswer.AddPair('edit', WorkspaceEditJson(AArguments.Items[0].Value, mEdits));
  mAnswer.AddPair('allWarnings', TJSONBool.Create(mSwitch.AllWarnings));
  Result := mAnswer;
end;

end.
