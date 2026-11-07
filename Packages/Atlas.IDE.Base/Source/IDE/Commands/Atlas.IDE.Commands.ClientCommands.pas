unit Atlas.IDE.Commands.ClientCommands;

// Client-Befehle der Code-Aktionen (#399), aus TAtlasIdeEditorCommands.RunCommand
// (Atlas.IDE.Commands.Editor, Beschreibung dort) ausgelagert: atlas.copyText,
// atlas.openFile, atlas.goToPosition (#915), atlas.showSignatureHelp (#1007),
// atlas.showUnitRelations (#896), die Befehle der fehlenden Unit (#550) und
// der Projektwarnung (#531) sowie die Umbaudialoge (Signatur ändern #100,
// Klasse verschieben #103 usw.), die den Server selbst fragen. Alle übrigen
// Befehle gehen als workspace/executeCommand an den Server.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Session,
  Atlas.IDE.Commands.EditorContext;

type
  /// <summary>Was ein Client-Befehl vom Editor braucht.</summary>
  TAtlasClientCommandHost = record
    /// <summary>Laufende Sitzung (Server bei Bedarf gestartet) oder nil.</summary>
    Session: TFunc<TLspSession>;
    /// <summary>Zeile für die Meldungsansicht.</summary>
    Say: TProc<string>;
    SignatureHelp: TProc;
    UnitRelations: TProc;
    Placeholders: TAtlasPlaceholdersProc;
  end;

  /// <summary>Client-Befehle der Code-Aktionen.</summary>
  TAtlasClientCommands = record
  public
    /// <summary>ACommand ausführen, wenn es ein Client-Befehl ist; False für Befehle des Servers.</summary>
    class function TryRun(const ACommand, AArgumentsJson: string; const AHost: TAtlasClientCommandHost): Boolean;
      static;
  end;

implementation

uses
  System.JSON,
  System.Generics.Collections,
  Vcl.Clipbrd,
  ToolsAPI,
  Atlas.Core.Completion.Snippets,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Editor.ChangeSignature,
  Atlas.IDE.Editor.MoveClass,
  Atlas.IDE.Editor.ExtractInterface,
  Atlas.IDE.Editor.ExtractSuperclass,
  Atlas.IDE.Editor.MoveMember,
  Atlas.IDE.Editor.PropertyFromAccessors,
  Atlas.IDE.Editor.InlineAccessor,
  Atlas.IDE.Editor.SafeDelete,
  Atlas.IDE.Editor.InvertBoolean,
  Atlas.IDE.Editor.DisableWarning,
  Atlas.IDE.Editor.MissingUnit,
  Atlas.IDE.Editor.PromoteVariable,
  Atlas.IDE.Editor.AnonymousMethod,
  Atlas.IDE.Editor.MethodKind,
  Atlas.IDE.Editor.TypeAlias,
  Atlas.IDE.Editor.EnumTables,
  Atlas.IDE.Editor.Overloads;

const
  cCopyTextCommand = 'atlas.copyText';
  cOpenFileCommand = 'atlas.openFile';
  cGoToPositionCommand = 'atlas.goToPosition';
  cShowSignatureHelpCommand = 'atlas.showSignatureHelp';
  cShowUnitRelationsCommand = 'atlas.showUnitRelations';

type
  /// <summary>Umbaudialog, der den Server selbst fragt (Signatur von Execute der Umbauten).</summary>
  TRefactoringRun = reference to procedure(ASession: TLspSession; const AArgumentsJson: string;
    APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);

  /// <summary>Client-Befehl ohne Sitzung (Signatur der Befehle von fehlender Unit und Projektwarnung).</summary>
  TArgumentsRun = reference to procedure(const AArgumentsJson: string; const AMessage: TProc<string>);

  TRefactoring = record
    Command: string;
    Run: TRefactoringRun;
  end;

  TArgumentsCommand = record
    Command: string;
    Run: TArgumentsRun;
  end;

function Refactoring(const ACommand: string; const ARun: TRefactoringRun): TRefactoring;
begin
  Result.Command := ACommand;
  Result.Run := ARun;
end;

function ArgumentsCommand(const ACommand: string; const ARun: TArgumentsRun): TArgumentsCommand;
begin
  Result.Command := ACommand;
  Result.Run := ARun;
end;

/// <summary>Umbaudialoge, die den Server selbst fragen, je mit ihrem Befehl.</summary>
function Refactorings: TArray<TRefactoring>;
begin
  Result := [
    Refactoring(TAtlasIdeChangeSignature.cClientCommand, TAtlasIdeChangeSignature.Execute),
    Refactoring(TAtlasIdePropertyFromAccessors.cClientCommand, TAtlasIdePropertyFromAccessors.Execute),
    Refactoring(TAtlasIdeInlineAccessor.cClientCommand, TAtlasIdeInlineAccessor.Execute),
    Refactoring(TAtlasIdeSafeDelete.cClientCommand, TAtlasIdeSafeDelete.Execute),
    Refactoring(TAtlasIdeInvertBoolean.cClientCommand, TAtlasIdeInvertBoolean.Execute),
    Refactoring(TAtlasIdeDisableWarning.cClientCommand, TAtlasIdeDisableWarning.Execute),
    Refactoring(TAtlasIdePromoteVariable.cClientCommand, TAtlasIdePromoteVariable.Execute),
    Refactoring(TAtlasIdeAnonymousMethod.cClientCommand, TAtlasIdeAnonymousMethod.Execute),
    Refactoring(TAtlasIdeMethodKind.cClientCommand, TAtlasIdeMethodKind.Execute),
    Refactoring(TAtlasIdeTypeAlias.cClientCommand, TAtlasIdeTypeAlias.Execute),
    Refactoring(TAtlasIdeTypeAlias.cInlineClientCommand, TAtlasIdeTypeAlias.ExecuteInline),
    Refactoring(TAtlasIdeEnumTables.cClientCommand, TAtlasIdeEnumTables.Execute),
    Refactoring(TAtlasIdeEnumTables.cSyncClientCommand, TAtlasIdeEnumTables.ExecuteSync),
    Refactoring(TAtlasIdeExtractInterface.cClientCommand, TAtlasIdeExtractInterface.Execute),
    Refactoring(TAtlasIdeExtractSuperclass.cClientCommand, TAtlasIdeExtractSuperclass.Execute),
    Refactoring(TAtlasIdeMoveMember.cClientCommand, TAtlasIdeMoveMember.Execute),
    Refactoring(TAtlasIdeMoveClass.cClientCommand, TAtlasIdeMoveClass.Execute)];
end;

/// <summary>Projektwarnung (#531) und fehlende Unit (#550), je mit ihrem Befehl.</summary>
function ArgumentsCommands: TArray<TArgumentsCommand>;
begin
  Result := [
    ArgumentsCommand(TAtlasIdeDisableWarning.cProjectCommand, TAtlasIdeDisableWarning.ExecuteProject),
    ArgumentsCommand(TAtlasIdeMissingUnit.cSearchPathCommand, TAtlasIdeMissingUnit.AddSearchPath),
    ArgumentsCommand(TAtlasIdeMissingUnit.cAddUnitCommand, TAtlasIdeMissingUnit.AddUnit),
    ArgumentsCommand(TAtlasIdeMissingUnit.cInfoCommand, TAtlasIdeMissingUnit.ShowInfo)];
end;

/// <summary>Argumente als Liste; nil, wenn sie weniger als ACount Einträge hat. Der Aufrufer gibt sie frei.</summary>
function ArgumentList(const AArgumentsJson: string; ACount: Integer; out AValue: TJSONValue): TJSONArray;
begin
  AValue := TJSONObject.ParseJSONValue(AArgumentsJson);
  Result := nil;
  if (AValue is TJSONArray) and (TJSONArray(AValue).Count >= ACount) then
  begin
    Result := TJSONArray(AValue);
  end;
end;

/// <summary>atlas.copyText: das erste Argument in die Zwischenablage.</summary>
procedure CopyText(const AArgumentsJson: string; const AHost: TAtlasClientCommandHost);
var
  mValue: TJSONValue;
  mList: TJSONArray;
begin
  mList := ArgumentList(AArgumentsJson, 1, mValue);
  try
    if (mList <> nil) and (mList.Items[0] is TJSONString) then
    begin
      Clipboard.AsText := mList.Items[0].Value;
      AHost.Say(TAtlasStrings.Text(TAtlasTextId.EditorTextCopied));
    end;
  finally
    mValue.Free;
  end;
end;

/// <summary>atlas.openFile: Datei der URI im ersten Argument öffnen.</summary>
procedure OpenFile(const AArgumentsJson: string);
var
  mValue: TJSONValue;
  mList: TJSONArray;
begin
  mList := ArgumentList(AArgumentsJson, 1, mValue);
  try
    if mList <> nil then
    begin
      TAtlasIdeNavigation.GoToLocation(TLspSession.UriToPath(mList.Items[0].Value), 0, 0);
    end;
  finally
    mValue.Free;
  end;
end;

/// <summary>atlas.goToPosition: Zeile und Zeichen (0-basiert, als Text) im oberen Editor (#915); True, wenn
/// gesprungen.</summary>
function GoToPosition(const AArgumentsJson: string): Boolean;
var
  mValue: TJSONValue;
  mList: TJSONArray;
begin
  mList := ArgumentList(AArgumentsJson, 2, mValue);
  try
    Result := mList <> nil;
    if Result then
    begin
      TAtlasIdeNavigation.GoToPosition(StrToIntDef(mList.Items[0].Value, 0), StrToIntDef(mList.Items[1].Value, 0));
    end;
  finally
    mValue.Free;
  end;
end;

/// <summary>Optionaler Rückruf.</summary>
procedure CallIfAssigned(const AProc: TProc);
begin
  if Assigned(AProc) then
  begin
    AProc();
  end;
end;

/// <summary>Befehle ohne Server: Zwischenablage, Datei, Position, Parameter-Hint, Unit-Beziehungen.</summary>
function TryEditorCommand(const ACommand, AArgumentsJson: string; const AHost: TAtlasClientCommandHost): Boolean;
begin
  Result := True;
  if ACommand = cCopyTextCommand then
  begin
    CopyText(AArgumentsJson, AHost);
  end
  else if ACommand = cOpenFileCommand then
  begin
    OpenFile(AArgumentsJson);
  end
  else if ACommand = cGoToPositionCommand then
  begin
    GoToPosition(AArgumentsJson);
  end
  else if ACommand = cShowSignatureHelpCommand then
  begin
    // Wie atlas.goToPosition, danach der Parameter-Hint an der Stelle (#1007).
    if GoToPosition(AArgumentsJson) then
    begin
      CallIfAssigned(AHost.SignatureHelp);
    end;
  end
  else if ACommand = cShowUnitRelationsCommand then
  begin
    // „Graph zeigen“ an einem Unit-Zyklus (#896).
    CallIfAssigned(AHost.UnitRelations);
  end
  else
  begin
    Result := False;
  end;
end;

/// <summary>„Überladung anlegen“ (#674); danach der Platzhalter-Modus über die Composition.</summary>
procedure RunOverloads(const AArgumentsJson: string; const AHost: TAtlasClientCommandHost);
var
  mPlaceholders: TAtlasPlaceholdersProc;
begin
  mPlaceholders := AHost.Placeholders;
  TAtlasIdeOverloads.Execute(AHost.Session(), AArgumentsJson,
    TAtlasUnopenedPolicies.FromSetting(TAtlasIdeSettings.Current.OpenForEdits), AHost.Say,
    procedure(const AView: IOTAEditView; const ABefore: string; AOffset: Integer;
      const AExpansion: TAtlasSnippetExpansion)
    begin
      if Assigned(mPlaceholders) then
      begin
        mPlaceholders(AView, ABefore, AOffset, AExpansion);
      end;
    end);
end;

/// <summary>Umbaudialoge und Befehle mit Argumenten aus den Tabellen.</summary>
function TryTableCommand(const ACommand, AArgumentsJson: string; const AHost: TAtlasClientCommandHost): Boolean;
var
  mRefactoring: TRefactoring;
  mCommand: TArgumentsCommand;
begin
  Result := True;
  for mRefactoring in Refactorings do
  begin
    if ACommand = mRefactoring.Command then
    begin
      mRefactoring.Run(AHost.Session(), AArgumentsJson,
        TAtlasUnopenedPolicies.FromSetting(TAtlasIdeSettings.Current.OpenForEdits), AHost.Say);
      Exit;
    end;
  end;
  for mCommand in ArgumentsCommands do
  begin
    if ACommand = mCommand.Command then
    begin
      mCommand.Run(AArgumentsJson, AHost.Say);
      Exit;
    end;
  end;
  Result := False;
end;

{ TAtlasClientCommands }

class function TAtlasClientCommands.TryRun(const ACommand, AArgumentsJson: string;
  const AHost: TAtlasClientCommandHost): Boolean;
begin
  Result := True;
  if ACommand = TAtlasIdeOverloads.cClientCommand then
  begin
    RunOverloads(AArgumentsJson, AHost);
  end
  else if not TryEditorCommand(ACommand, AArgumentsJson, AHost) then
  begin
    Result := TryTableCommand(ACommand, AArgumentsJson, AHost);
  end;
end;

end.
