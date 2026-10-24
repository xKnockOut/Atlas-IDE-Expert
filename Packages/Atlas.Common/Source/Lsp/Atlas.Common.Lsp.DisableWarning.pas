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
    if SameText(ScopeNames[Scope], AName) then
    begin
      AScope := Scope;
      Exit(True);
    end;
  AScope := TDisableWarningScope.Line;
  Result := False;
end;

function SwitchHint(const ASwitch: TDisableWarningSwitch): string;
begin
  Result := ASwitch.OffText;
  if ASwitch.AllWarnings then
    Result := Result + ': betrifft alle Warnungen';
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
    Result.AddPair('isPreferred', TJSONBool.Create(True));
  Result.AddPair('command', Command);
end;

function ScopeAction(const AOptions: TDisableWarningOptions; const AUri: string; ALine: Integer;
  const ASwitch: TDisableWarningSwitch; AScope: TDisableWarningScope; const ATitle: string;
  APreferred: Boolean): TJSONObject;
var
  Arguments: TJSONArray;
begin
  Arguments := TJSONArray.Create;
  Arguments.Add(AUri);
  Arguments.AddElement(TJSONNumber.Create(ALine));
  Arguments.Add(ASwitch.Code);
  Arguments.Add(TLspDisableWarning.ScopeName(AScope));
  Arguments.AddElement(TJSONBool.Create(AOptions.AskReason));
  Result := CommandAction(ATitle, TLspDisableWarning.ClientCommand, Arguments, APreferred);
end;

class function TLspDisableWarning.Actions(const AOptions: TDisableWarningOptions; ATree: TSyntaxTree;
  const AUri: string; AFirstLine, ALastLine: Integer; const AMessages: TArray<TCompilerMessage>):
  TArray<TJSONObject>;
var
  Seen: TDictionary<string, Boolean>;
  Message: TCompilerMessage;
  Switch: TDisableWarningSwitch;
  Routine: TSyntaxNode;
  Arguments: TJSONArray;
  HasHeader: Boolean;
begin
  Result := nil;
  if not AOptions.Enabled or (ATree = nil) then
    Exit;
  HasHeader := TDisableWarning.HeaderEndLine(ATree) >= 0;
  Seen := TDictionary<string, Boolean>.Create;
  try
    for Message in AMessages do
    begin
      if (Message.Line < AFirstLine) or (Message.Line > ALastLine) or
        not TDisableWarning.SwitchFor(Message.Code, AOptions.Version, Switch) or
        Seen.ContainsKey(Switch.Code + '@' + IntToStr(Message.Line)) then
        Continue;
      Seen.Add(Switch.Code + '@' + IntToStr(Message.Line), True);
      // Ablaufmeldungen prüft der Compiler am Ende der Routine: Ein Schalter um die Zeile wirkte nicht.
      if not Switch.RoutineWide then
        Result := Result + [ScopeAction(AOptions, AUri, Message.Line, Switch, TDisableWarningScope.Line,
          Format('%s hier abschalten (%s)', [Switch.Code, SwitchHint(Switch)]), True)];
      Routine := TDisableWarning.RoutineAt(ATree, Message.Line);
      if Routine <> nil then
        Result := Result + [ScopeAction(AOptions, AUri, Message.Line, Switch, TDisableWarningScope.Routine,
          Format('%s in %s abschalten (%s)', [Switch.Code, Routine.Name, SwitchHint(Switch)]),
          Switch.RoutineWide)];
      if HasHeader then
        Result := Result + [ScopeAction(AOptions, AUri, Message.Line, Switch, TDisableWarningScope.UnitWide,
          Format('%s in der ganzen Unit abschalten (%s)', [Switch.Code, SwitchHint(Switch)]),
          Switch.RoutineWide and (Routine = nil))];
      if Switch.Identifier <> '' then
      begin
        Arguments := TJSONArray.Create;
        Arguments.Add(AUri);
        Arguments.Add(Switch.Code);
        Arguments.Add(Switch.Identifier);
        Result := Result + [CommandAction(Format('%s im ganzen Projekt abschalten (Projektoptionen)',
          [Switch.Code]), ProjectCommand, Arguments, False)];
      end;
    end;
  finally
    Seen.Free;
  end;
end;

class function TLspDisableWarning.Execute(const AArguments: TJSONArray; const AText: string; ATree: TSyntaxTree;
  const AVersion: string): TJSONValue;
var
  Uri, Reason: string;
  Line: Integer;
  Scope: TDisableWarningScope;
  Switch: TDisableWarningSwitch;
  Edits: TArray<TTextEdit>;
  Edit: TTextEdit;
  Answer, Document, TextDocument, Item, WorkspaceEdit: TJSONObject;
  Items, Changes: TJSONArray;
begin
  if (AArguments = nil) or (AArguments.Count < 4) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Argumente "uri", "line", "code" und "scope" fehlen');
  Uri := AArguments.Items[0].Value;
  Line := StrToIntDef(AArguments.Items[1].Value, -1);
  if not TryParseScope(AArguments.Items[3].Value, Scope) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Unbekannter Bereich: ' + AArguments.Items[3].Value);
  Reason := '';
  if AArguments.Count > 4 then
    Reason := AArguments.Items[4].Value;
  if not TDisableWarning.SwitchFor(AArguments.Items[2].Value, AVersion, Switch) then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed,
      AArguments.Items[2].Value + ' ist keine Warnung und kein Hinweis.');
  if not TDisableWarning.Edits(AText, ATree, Line, Switch, Scope, Reason, Edits) then
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed,
      'An dieser Stelle gibt es keinen passenden Bereich (Zeile, Routine oder Unit-Kopf).');
  Items := TJSONArray.Create;
  for Edit in Edits do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('range', TLspPositions.RangeToJson(Edit.Range));
    Item.AddPair('newText', Edit.NewText);
    Items.AddElement(Item);
  end;
  TextDocument := TJSONObject.Create;
  TextDocument.AddPair('uri', Uri);
  TextDocument.AddPair('version', TJSONNull.Create);
  Document := TJSONObject.Create;
  Document.AddPair('textDocument', TextDocument);
  Document.AddPair('edits', Items);
  Changes := TJSONArray.Create;
  Changes.AddElement(Document);
  WorkspaceEdit := TJSONObject.Create;
  WorkspaceEdit.AddPair('documentChanges', Changes);
  Answer := TJSONObject.Create;
  Answer.AddPair('edit', WorkspaceEdit);
  Answer.AddPair('allWarnings', TJSONBool.Create(Switch.AllWarnings));
  Result := Answer;
end;

end.
