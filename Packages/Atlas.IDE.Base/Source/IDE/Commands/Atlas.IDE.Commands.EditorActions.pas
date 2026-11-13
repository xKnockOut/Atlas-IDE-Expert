unit Atlas.IDE.Commands.EditorActions;

// Code-Aktionen im Editor (#399), Vorfahr von TAtlasIdeEditorCommands
// (Atlas.IDE.Commands.Editor, Beschreibung dort): Auswahl in einem Fenster wie
// die Befehlspalette, Vorschau (#663), Änderung und danach der Befehl; die
// Client-Befehle stehen in Atlas.IDE.Commands.ClientCommands.

interface

uses
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Lsp.Session,
  Atlas.IDE.Commands.EditorServer;

type
  /// <summary>Code-Aktionen im Editor.</summary>
  TAtlasEditorActionCommands = class(TAtlasEditorServerCommands)
  protected
    class procedure Apply(const AAction: TLspCodeAction); static;
    /// <summary>Vorschau der Änderungen mit AAction.Preview als Hinweis; True, wenn übernommen werden soll.</summary>
    class function ConfirmPreview(const AAction: TLspCodeAction): Boolean; static;
    /// <summary>Abwählbare Teile (#2054) im Dialog wählen und abgewählte Edits entfernen; False bei Abbrechen.
    /// </summary>
    class function ChooseParts(var AAction: TLspCodeAction): Boolean; static;
    class procedure RunCommand(const ACommand, AArgumentsJson: string); static;
    /// <summary>Code-Aktionen des Servers für ARange; False mit Meldung bei einem Fehler.</summary>
    class function FetchActions(const AFileName: string; const ARange: TLspRange;
      out AFound: TArray<TLspCodeAction>): Boolean; static;
    /// <summary>Aktionen zur Wahl in einem Fenster wie die Befehlspalette.</summary>
    class procedure ShowActions(const AUsable: TArray<TLspCodeAction>); static;
  public
    class procedure CodeActions; static;
    /// <summary>AFound zur Wahl wie bei CodeActions (bevorzugte zuerst), etwa die Aktionen für ein nicht
    /// sichtbares Mitglied aus der Vervollständigung (#2108); ohne Aktion eine Meldung.</summary>
    class procedure OfferActions(const AFound: TArray<TLspCodeAction>); static;
    /// <summary>Code-Aktion anwenden: erst die Änderung, dann der Befehl; auch für das Erzeugen-Menü (#719).
    /// </summary>
    class procedure ApplyAction(const AAction: TLspCodeAction); static;
    /// <summary>Code-Aktion mit Kennung ATag (data.tag) für ARange der oberen Datei holen und anwenden, etwa
    /// „Entfernen“ aus dem Tooltip eines uses-Eintrags (#621). Ohne solche Aktion eine Zeile in der
    /// Meldungsansicht.</summary>
    class procedure ApplyTagged(const ARange: TLspRange; const ATag: string); static;
  end;

implementation

uses
  System.SysUtils,
  System.Types,
  System.JSON,
  Vcl.Forms,
  Vcl.Controls,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Commands.Palette,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.Core.Results.Model,
  Atlas.UI.Strings,
  Atlas.UI.Commands.Strings,
  Atlas.UI.Commands.Palette,
  Atlas.UI.Results.View,
  Atlas.UI.Results.RenamePreview,
  Atlas.UI.Editor.ActionChoices,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Commands.ClientCommands,
  Atlas.IDE.Foundation.Host;

function KindCaption(const AKind: string): string;
begin
  if AKind.StartsWith('quickfix') then
  begin
    Result := TAtlasCommandsStrings.Text(TAtlasCommandsTextId.EditorKindFix);
  end
  else if AKind.StartsWith('refactor') then
  begin
    Result := TAtlasCommandsStrings.Text(TAtlasCommandsTextId.EditorKindRefactor);
  end
  else if AKind.StartsWith('source') then
  begin
    Result := TAtlasCommandsStrings.Text(TAtlasCommandsTextId.EditorKindSource);
  end
  else
  begin
    Result := '';
  end;
end;

/// <summary>Rang einer Aktion in der Liste: 0 bevorzugt, 1 übrige, 2 gesperrt (Hinweis statt Aktion, #663).</summary>
function ActionRank(const AAction: TLspCodeAction): Integer;
begin
  if AAction.Disabled <> '' then
  begin
    Result := 2;
  end
  else if AAction.Preferred then
  begin
    Result := 0;
  end
  else
  begin
    Result := 1;
  end;
end;

/// <summary>Bevorzugte zuerst, sonst die Reihenfolge des Servers; gesperrte am Ende, wählen nennt den Grund.</summary>
function OrderedActions(const AFound: TArray<TLspCodeAction>): TArray<TLspCodeAction>;
var
  mRank: Integer;
  mAction: TLspCodeAction;
begin
  Result := nil;
  for mRank := 0 to 2 do
  begin
    for mAction in AFound do
    begin
      if ActionRank(mAction) = mRank then
      begin
        Result := Result + [mAction];
      end;
    end;
  end;
end;

/// <summary>Einträge des Fensters zu AUsable; Id = Index.</summary>
function ActionCommands(const AUsable: TArray<TLspCodeAction>): TArray<TAtlasCommand>;
var
  mIndex: Integer;
  mCommand: TAtlasCommand;
begin
  Result := nil;
  for mIndex := 0 to High(AUsable) do
  begin
    mCommand := Default(TAtlasCommand);
    mCommand.Id := IntToStr(mIndex);
    mCommand.Caption := AUsable[mIndex].Title;
    mCommand.Path := KindCaption(AUsable[mIndex].Kind);
    if AUsable[mIndex].Disabled <> '' then
    begin
      mCommand.Path := TAtlasCommandsStrings.Text(TAtlasCommandsTextId.EditorActionNote);
    end;
    if AUsable[mIndex].Preferred then
    begin
      mCommand.ShortCut := '★';
    end;
    Result := Result + [mCommand];
  end;
end;

class function TAtlasEditorActionCommands.FetchActions(const AFileName: string; const ARange: TLspRange;
  out AFound: TArray<TLspCodeAction>): Boolean;
begin
  Result := True;
  AFound := nil;
  Screen.Cursor := crHourGlass;
  try
    try
      AFound := Session.CodeActions(AFileName, ARange);
    except
      on E: ELspClientError do
      begin
        Say(TAtlasStrings.Fmt(TAtlasTextId.EditorFailed, [E.Message]));
        Result := False;
      end;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
end;

class procedure TAtlasEditorActionCommands.ShowActions(const AUsable: TArray<TLspCodeAction>);
var
  mWindow: TAtlasPaletteWindow;
  mUsable: TArray<TLspCodeAction>;
begin
  mUsable := AUsable;
  mWindow := TAtlasPaletteWindow.CreatePalette(Application, ActionCommands(mUsable), nil, TAtlasIdeStyle.Colors);
  mWindow.KeepOrder := True;
  mWindow.OnExecute :=
    procedure(ACommand: TAtlasCommand)
    var
      mChosen: Integer;
    begin
      mChosen := StrToIntDef(ACommand.Id, -1);
      if (mChosen >= 0) and (mChosen <= High(mUsable)) then
      begin
        TAtlasGuard.Run(TAtlasFeature.EditorCommands,
          procedure
          begin
            Apply(mUsable[mChosen]);
          end);
      end;
    end;
  mWindow.ShowOver(TAtlasIdeHost.PopupArea);
end;

class procedure TAtlasEditorActionCommands.CodeActions;
var
  mView: IOTAEditView;
  mFileName: string;
  mLines: TArray<string>;
  mSelection: TLspRange;
  mFound: TArray<TLspCodeAction>;
begin
  if Current(mView, mFileName, mLines, mSelection) and FetchActions(mFileName, mSelection, mFound) then
  begin
    OfferActions(mFound);
  end;
end;

class procedure TAtlasEditorActionCommands.OfferActions(const AFound: TArray<TLspCodeAction>);
var
  mUsable: TArray<TLspCodeAction>;
begin
  mUsable := OrderedActions(AFound);
  if Length(mUsable) = 0 then
  begin
    Say(TAtlasCommandsStrings.Text(TAtlasCommandsTextId.EditorNoActions));
    Exit;
  end;
  ShowActions(mUsable);
end;

class procedure TAtlasEditorActionCommands.ApplyAction(const AAction: TLspCodeAction);
begin
  Apply(AAction);
end;

class procedure TAtlasEditorActionCommands.ApplyTagged(const ARange: TLspRange; const ATag: string);
var
  mView: IOTAEditView;
  mFileName: string;
  mLines: TArray<string>;
  mSelection: TLspRange;
  mFound: TArray<TLspCodeAction>;
  mAction: TLspCodeAction;
begin
  // Current gleicht den Text ab; der Bereich stammt aus den Diagnosen desselben Stands.
  if not Current(mView, mFileName, mLines, mSelection) then
  begin
    Exit;
  end;
  try
    mFound := Session.CodeActions(mFileName, ARange);
  except
    on E: ELspClientError do
    begin
      Say(TAtlasStrings.Fmt(TAtlasTextId.EditorFailed, [E.Message]));
      Exit;
    end;
  end;
  for mAction in mFound do
  begin
    if SameText(mAction.Tag, ATag) and (mAction.Disabled = '') then
    begin
      Apply(mAction);
      Exit;
    end;
  end;
  Say(TAtlasCommandsStrings.Text(TAtlasCommandsTextId.UsesActionMissing));
end;

class function TAtlasEditorActionCommands.ChooseParts(var AAction: TLspCodeAction): Boolean;
var
  mTitles: TArray<string>;
  mChoice: TLspCodeActionChoice;
  mChosen: TArray<Boolean>;
begin
  Result := True;
  if AAction.Choices = nil then
  begin
    Exit;
  end;
  mTitles := nil;
  for mChoice in AAction.Choices do
  begin
    mTitles := mTitles + [mChoice.Title];
  end;
  Result := TAtlasActionChoicesDialog.Choose(AAction.Title, AAction.Preview, mTitles, mChosen);
  if Result then
  begin
    AAction := AAction.WithChoices(mChosen);
  end;
end;

class function TAtlasEditorActionCommands.ConfirmPreview(const AAction: TLspCodeAction): Boolean;
var
  mPreview: TArray<TAtlasResultEntry>;
  mOpen: TAtlasResultsOpen;
begin
  mPreview := TAtlasResults.RenamePreview(AAction.Edit,
    function(const AFileName: string): string
    begin
      Result := TAtlasIdeWorkspaceEdit.CurrentText(AFileName);
    end);
  mOpen :=
    procedure(const AFileName: string; ALine, ACharacter: Integer)
    begin
      TAtlasIdeNavigation.GoToLocation(AFileName, ALine, ACharacter);
    end;
  Result := TAtlasRenamePreview.Execute(AAction.Title, AAction.Preview, TAtlasResults.Group(mPreview), mOpen);
end;

class procedure TAtlasEditorActionCommands.Apply(const AAction: TLspCodeAction);
var
  mOutcome: TAtlasWorkspaceEditResult;
  mAction: TLspCodeAction;
begin
  mAction := AAction;
  if mAction.Disabled <> '' then
  begin
    Say(TAtlasCommandsStrings.Fmt(TAtlasCommandsTextId.EditorActionDisabled, [mAction.Title, mAction.Disabled]));
    Exit;
  end;
  // Abwählbare Teile (#2054): erst wählen, dann die gewohnte Vorschau der übrigen Änderungen.
  if not ChooseParts(mAction) then
  begin
    Exit;
  end;
  // LSP: erst die Änderung, dann der Befehl.
  if not mAction.Edit.IsEmpty then
  begin
    if (mAction.Preview <> '') and not ConfirmPreview(mAction) then
    begin
      Exit;
    end;
    mOutcome := TAtlasIdeWorkspaceEdit.Apply(mAction.Edit,
      TAtlasUnopenedPolicies.FromSetting(TAtlasIdeSettings.Current.OpenForEdits),
      mAction.Title);
    if mOutcome.Error <> '' then
    begin
      Say(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [mOutcome.Error]));
      Exit;
    end;
    if mOutcome.Written > 0 then
    begin
      Say(TAtlasStrings.Fmt(TAtlasTextId.EditWritten, [mOutcome.Written]));
    end;
  end;
  if mAction.Edit.Unsupported > 0 then
  begin
    Say(TAtlasStrings.Fmt(TAtlasTextId.EditUnsupported, [mAction.Edit.Unsupported]));
  end;
  if mAction.Command <> '' then
  begin
    RunCommand(mAction.Command, mAction.ArgumentsJson);
  end;
end;

class procedure TAtlasEditorActionCommands.RunCommand(const ACommand, AArgumentsJson: string);
var
  mHost: TAtlasClientCommandHost;
  mRunning: TLspSession;
  mAnswer: TJSONValue;
begin
  mHost.Session :=
    function: TLspSession
    begin
      Result := Session;
    end;
  mHost.Say :=
    procedure(AText: string)
    begin
      Say(AText);
    end;
  mHost.SignatureHelp := FOnSignatureHelp;
  mHost.UnitRelations := FOnUnitRelations;
  mHost.Placeholders := FOnPlaceholders;
  if TAtlasClientCommands.TryRun(ACommand, AArgumentsJson, mHost) then
  begin
    Exit;
  end;
  mRunning := Session;
  if mRunning = nil then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  try
    mAnswer := mRunning.RunCommand(ACommand, AArgumentsJson, cCommandTimeoutMs);
    // Ein workspace/applyEdit des Servers (#397) läuft erst nach dieser Antwort im Hauptthread.
    // Eine Antwort als Text zeigen.
    try
      if (mAnswer is TJSONString) and (mAnswer.Value <> '') then
      begin
        Say(mAnswer.Value);
      end;
    finally
      mAnswer.Free;
    end;
  except
    on E: ELspClientError do
      Say(TAtlasStrings.Fmt(TAtlasTextId.EditorFailed, [E.Message]));
  end;
end;

end.
