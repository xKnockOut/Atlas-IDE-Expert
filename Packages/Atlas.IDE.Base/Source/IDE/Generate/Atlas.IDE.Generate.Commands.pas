unit Atlas.IDE.Generate.Commands;

// Erzeugen-Menü (#719) in der IDE: Alt+Einfg (keys.generateMenu.key), Atlas-
// Untermenü im Editor-Kontextmenü, Menü Atlas und Befehlspalette
// (Atlas.GenerateMenu) öffnen am Cursor ein Menü mit den Gruppen Erzeugen,
// Umschließen (nur mit Markierung) und Vorlagen.
// Ablauf: Puffer an den Server (Sync), dann
//   - atlas.server.slashMenu: Orte an der Stelle und die passenden
//     Schnellbefehle (Ortsregel aus #293), dazu „Interface implementieren“;
//   - textDocument/codeAction: Code-Aktionen der Art refactor;
//   - Code-Vorlagen der Vervollständigung (#51, #487, #665), deren Kontext zu
//     den Orten passt.
// Gewählt wird im Fenster (Atlas.UI.Generate.Window); Auswahl-Listen holt
// atlas.server.slashChoices, ausgeführt wird über atlas.server.slashRun (ein
// Rückgängig-Schritt mit der Beschriftung als Titel), Vorlagen setzt die
// Vervollständigung mit Platzhaltern ein, Code-Aktionen wie im Fenster
// „Code-Aktionen“. Zuletzt gewählte Einträge stehen in
// %APPDATA%\Atlas\generate-recent.txt (eine Kennung je Zeile).
// Show(AGroups) öffnet das Menü nur mit den genannten Gruppen (#759 „Neu mit
// Atlas“ zeigt so nur die Vorlagen). Mit keys.generateMenu aus ruht alles;
// das Kürzel belegt Atlas dann nicht (Atlas.IDE.Commands.Bindings).
// Meldungen nur als Zeile in der Meldungsansicht.

interface

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Completion.Snippets,
  Atlas.Core.Generate.Menu;

type
  TAtlasIdeGenerate = class
  private class var
    FSessionOf: TFunc<TLspSession>;
    FMessage: TProc<string>;
    FSnippets: TFunc<TAtlasSnippetList>;
    FInsertSnippet: TProc<IOTAEditView, TAtlasSnippet>;
    FApplyAction: TProc<TLspCodeAction>;
    FRecent: TAtlasGenerateRecent;
    FRecentLoaded: Boolean;
    /// <summary>Verlauf war beim Lesen gesperrt: Remember überschreibt ihn nicht.</summary>
    FRecentKept: Boolean;
  private
    class function Session: TLspSession; static;
    class procedure Say(const AText: string); static;
    class procedure LoadRecent; static;
    class procedure Remember(const AEntry: TAtlasGenerateEntry); static;
  public
    /// <summary>ASessionOf: laufende Sitzung oder nil; AMessage: Zeile für die Meldungsansicht; ASnippets: alle
    /// Code-Vorlagen der Vervollständigung (leer, wenn sie aus sind); AInsertSnippet setzt eine Vorlage mit
    /// Platzhaltern am Cursor ein; AApplyAction wendet eine Code-Aktion an (Editorbefehle; als Haken, damit das
    /// Erzeugen-Menü sie nicht importiert).</summary>
    class procedure Install(const ASessionOf: TFunc<TLspSession>; const AMessage: TProc<string>;
      const ASnippets: TFunc<TAtlasSnippetList>; const AInsertSnippet: TProc<IOTAEditView, TAtlasSnippet>;
      const AApplyAction: TProc<TLspCodeAction>); static;
    class procedure Uninstall; static;
    /// <summary>Menü mit allen eingestellten Gruppen.</summary>
    class procedure Show; overload; static;
    /// <summary>Menü nur mit den Gruppen aus AGroups (in der eingestellten Reihenfolge).</summary>
    class procedure Show(const AGroups: TArray<TAtlasGenerateGroup>); overload; static;
    /// <summary>%APPDATA%\Atlas\generate-recent.txt.</summary>
    class function RecentFile: string; static;
  end;

implementation

uses
  Winapi.Windows,
  System.Types,
  System.IOUtils,
  System.JSON,
  Vcl.Forms,
  Vcl.Controls,
  Atlas.Text.Lines,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Generate.Protocol,
  Atlas.UI.Strings,
  Atlas.UI.Generate.Strings,
  Atlas.UI.Generate.Window,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Foundation.Settings,
  Atlas.Core.Editor.WorkspacePlan;

const
  // Wie die Code-Aktionen: Der Server darf etwas rechnen (Vorfahren, Index).
  cCommandTimeoutMs = 30000;

function LineAt(const ALines: TArray<string>; AIndex: Integer): string;
begin
  Result := '';
  if (AIndex >= 0) and (AIndex < Length(ALines)) then
  begin
    Result := ALines[AIndex];
  end;
end;

/// <summary>Caret des Editors in Bildschirmkoordinaten; False ohne Caret.</summary>
function CaretRect(out ARect: TRect): Boolean;
var
  mInfo: TGUIThreadInfo;
begin
  FillChar(mInfo, SizeOf(mInfo), 0);
  mInfo.cbSize := SizeOf(mInfo);
  Result := GetGUIThreadInfo(GetCurrentThreadId, mInfo) and (mInfo.hwndCaret <> 0);
  if not Result then
  begin
    Exit;
  end;
  ARect := mInfo.rcCaret;
  MapWindowPoints(mInfo.hwndCaret, 0, ARect, 2);
end;

{ TAtlasIdeGenerate }

class procedure TAtlasIdeGenerate.Install(const ASessionOf: TFunc<TLspSession>; const AMessage: TProc<string>;
  const ASnippets: TFunc<TAtlasSnippetList>; const AInsertSnippet: TProc<IOTAEditView, TAtlasSnippet>;
  const AApplyAction: TProc<TLspCodeAction>);
begin
  FSessionOf := ASessionOf;
  FMessage := AMessage;
  FSnippets := ASnippets;
  FInsertSnippet := AInsertSnippet;
  FApplyAction := AApplyAction;
  FRecent := TAtlasGenerateRecent.Create;
  FRecentLoaded := False;
  FRecentKept := False;
end;

class procedure TAtlasIdeGenerate.Uninstall;
begin
  FreeAndNil(FRecent);
  FRecentLoaded := False;
  FSessionOf := nil;
  FMessage := nil;
  FSnippets := nil;
  FInsertSnippet := nil;
  FApplyAction := nil;
end;

class function TAtlasIdeGenerate.Session: TLspSession;
begin
  Result := nil;
  if Assigned(FSessionOf) then
  begin
    Result := FSessionOf();
  end;
end;

class procedure TAtlasIdeGenerate.Say(const AText: string);
begin
  if Assigned(FMessage) then
  begin
    FMessage(AText);
  end;
end;

class function TAtlasIdeGenerate.RecentFile: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('APPDATA'), 'Atlas'), 'generate-recent.txt');
end;

class procedure TAtlasIdeGenerate.LoadRecent;
begin
  if FRecentLoaded or (FRecent = nil) then
  begin
    Exit;
  end;
  FRecentLoaded := True;
  // Eine Kennung je Zeile, jeder Text ist lesbar. Gesperrt: leer beginnen und die Datei nicht überschreiben;
  // TAtlasDataFile protokolliert das ohne Pfad.
  FRecentKept := not TAtlasDataFile.Writable(TAtlasDataFile.Load(RecentFile, 'Verlauf des Erzeugen-Menüs',
    function(const AText: string): Boolean
    begin
      FRecent.LoadFromText(AText);
      Result := True;
    end));
  if FRecentKept then
  begin
    FRecent.Clear;
  end;
end;

class procedure TAtlasIdeGenerate.Remember(const AEntry: TAtlasGenerateEntry);
begin
  if FRecent = nil then
  begin
    Exit;
  end;
  LoadRecent;
  FRecent.Chosen(AEntry.Id);
  if FRecentKept then
  begin
    Exit;
  end;
  try
    TAtlasDataFile.Write(RecentFile, FRecent.ToText);
  except
    on E: Exception do
      TAtlasDataFile.ReportNotWritten('Verlauf des Erzeugen-Menüs', E);
  end;
end;

class procedure TAtlasIdeGenerate.Show;
begin
  Show(nil);
end;

/// <summary>Stelle für den Server und Bereich für die Code-Aktionen aus Cursor bzw. Markierung.</summary>
procedure SpotOf(const AView: IOTAEditView; const ALines: TArray<string>; ATabWidth: Integer;
  out ASpot: TAtlasGenerateSpot; out ARange: TLspRange);
var
  mBlock: IOTAEditBlock;
  mCursor: TOTAEditPos;
  mStartLine, mStartChar, mEndLine, mEndChar: Integer;
begin
  mCursor := AView.CursorPos;
  mStartLine := mCursor.Line - 1;
  mStartChar := TLspSession.ColumnToIndex(LineAt(ALines, mStartLine), mCursor.Col, ATabWidth);
  ARange.StartPos := TLspTextPosition.Create(mStartLine, mStartChar);
  ARange.EndPos := ARange.StartPos;
  ASpot := TAtlasGenerateSpot.Create(TLspSession.PathToUri(AView.Buffer.FileName), mStartLine, mStartChar, -1);
  mBlock := AView.Block;
  if (mBlock = nil) or not mBlock.IsValid or (mBlock.Size = 0) then
  begin
    Exit;
  end;
  mStartLine := mBlock.StartingRow - 1;
  mStartChar := TLspSession.ColumnToIndex(LineAt(ALines, mStartLine), mBlock.StartingColumn, ATabWidth);
  mEndLine := mBlock.EndingRow - 1;
  mEndChar := TLspSession.ColumnToIndex(LineAt(ALines, mEndLine), mBlock.EndingColumn, ATabWidth);
  ARange.StartPos := TLspTextPosition.Create(mStartLine, mStartChar);
  ARange.EndPos := TLspTextPosition.Create(mEndLine, mEndChar);
  // Umschließen beginnt an der ersten Zeile der Markierung.
  ASpot := TAtlasGenerateSpot.Create(ASpot.Uri, mStartLine, mStartChar,
    TAtlasGenerateMenu.SelectionEndLine(mStartLine, mEndLine, mEndChar, True));
end;

/// <summary>Führt einen Schnellbefehl über atlas.server.slashRun aus: ein Rückgängig-Schritt.</summary>
procedure RunSlash(const AView: IOTAEditView; ASession: TLspSession; const ASpot: TAtlasGenerateSpot;
  const AEntry: TAtlasGenerateEntry; const AArgument: string; const ASay: TProc<string>);
var
  mFileName, mReason: string;
  mAnswer: TJSONValue;
  mEdits: TArray<TLspTextEdit>;
  mEdit: TLspWorkspaceEdit;
  mOutcome: TAtlasWorkspaceEditResult;
  mDone: Boolean;
begin
  mFileName := AView.Buffer.FileName;
  ASession.Sync(mFileName, TAtlasEditorBuffer.Text(AView.Buffer));
  try
    mAnswer := ASession.RunCommand(TAtlasGenerateProtocol.cRunCommand,
      TAtlasGenerateProtocol.RunArguments(ASpot, AEntry.Name, AArgument), cCommandTimeoutMs);
  except
    on E: ELspClientError do
    begin
      ASay(TAtlasGenerateStrings.Fmt(TAtlasGenerateTextId.GenerateFailed, [E.Message]));
      Exit;
    end;
  end;
  try
    mDone := TAtlasGenerateProtocol.ParseRun(mAnswer, mEdits, mReason);
  finally
    mAnswer.Free;
  end;
  if not mDone then
  begin
    ASay(TAtlasGenerateStrings.Fmt(TAtlasGenerateTextId.GenerateFailed, [mReason]));
    Exit;
  end;
  mEdit := Default(TLspWorkspaceEdit);
  mEdit.Files := [Default(TLspFileEdits)];
  mEdit.Files[0].FileName := mFileName;
  mEdit.Files[0].Edits := mEdits;
  mOutcome := TAtlasIdeWorkspaceEdit.Apply(mEdit, TAtlasUnopenedPolicy.WriteToDisk,
    TAtlasGenerateTexts.EntryCaption(AEntry));
  if mOutcome.Error <> '' then
  begin
    ASay(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [mOutcome.Error]));
  end;
end;

type
  /// <summary>Was das Menü zeigt: Einträge und die Quellen, auf die Code-Aktionen und Vorlagen verweisen.</summary>
  TMenuContent = record
    Entries: TArray<TAtlasGenerateEntry>;
    Actions: TArray<TLspCodeAction>;
    Snippets: TAtlasSnippetList;
  end;

/// <summary>Vorderste Ansicht und laufender Server; sonst eine Meldung und False.</summary>
function ReadyToShow(out AView: IOTAEditView; out ASession: TLspSession): Boolean;
var
  mEditors: IOTAEditorServices;
begin
  Result := False;
  AView := nil;
  ASession := nil;
  if not TAtlasIdeSettings.Current.GenerateMenu then
  begin
    TAtlasIdeGenerate.Say(TAtlasGenerateStrings.Text(TAtlasGenerateTextId.GenerateMenuOff));
    Exit;
  end;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    AView := mEditors.TopView;
  end;
  if (AView = nil) or (AView.Buffer = nil) then
  begin
    TAtlasIdeGenerate.Say(TAtlasStrings.Text(TAtlasTextId.ResultsNothing));
    Exit;
  end;
  ASession := TAtlasIdeGenerate.Session;
  Result := ASession <> nil;
  if not Result then
  begin
    TAtlasIdeGenerate.Say(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
  end;
end;

/// <summary>Eingestellte Gruppen; mit AGroups nur diese.</summary>
function MenuOptions(const AGroups: TArray<TAtlasGenerateGroup>): TAtlasGenerateOptions;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := TAtlasGenerateOptions.Create(mSettings.GenerateMenuGroups, mSettings.GenerateMenuHidden,
    mSettings.GenerateMenuRecentFirst, mSettings.GenerateMenuShowCommandNames);
  if Length(AGroups) > 0 then
  begin
    Result := Result.Only(AGroups);
  end;
end;

/// <summary>Orte und Schnellbefehle vom Server; False mit Meldung, wenn er nicht antwortet.</summary>
function ServerMenu(ASession: TLspSession; const ASpot: TAtlasGenerateSpot;
  out AMenu: TAtlasGenerateServerMenu): Boolean;
var
  mAnswer: TJSONValue;
begin
  AMenu := Default(TAtlasGenerateServerMenu);
  try
    mAnswer := ASession.RunCommand(TAtlasGenerateProtocol.cMenuCommand, TAtlasGenerateProtocol.MenuArguments(ASpot),
      cCommandTimeoutMs);
  except
    on E: ELspClientError do
    begin
      TAtlasIdeGenerate.Say(TAtlasGenerateStrings.Fmt(TAtlasGenerateTextId.GenerateFailed, [E.Message]));
      Exit(False);
    end;
  end;
  try
    AMenu := TAtlasGenerateProtocol.ParseMenu(mAnswer);
  finally
    mAnswer.Free;
  end;
  Result := True;
end;

/// <summary>Code-Aktionen der Art refactor im Bereich; nil, wenn der Server sie nicht liefert.</summary>
function RefactorActions(ASession: TLspSession; const AFileName: string; const ARange: TLspRange):
  TArray<TLspCodeAction>;
begin
  try
    Result := ASession.CodeActions(AFileName, ARange);
  except
    on E: ELspClientError do
    begin
      TAtlasGuard.Log('Erzeugen-Menü: Code-Aktionen fehlen (' + TAtlasGuard.MessageText(E.Message) + ')');
      Result := nil;
    end;
  end;
end;

/// <summary>Einträge aller Gruppen sammeln: Schnellbefehle, Code-Aktionen, Vorlagen; False, wenn der Server nicht
/// antwortet.</summary>
function CollectMenu(ASession: TLspSession; const AFileName: string; const ASpot: TAtlasGenerateSpot;
  const ARange: TLspRange; const AOptions: TAtlasGenerateOptions; out AContent: TMenuContent): Boolean;
var
  mMenu: TAtlasGenerateServerMenu;
begin
  AContent := Default(TMenuContent);
  // Orte und Schnellbefehle; die Orte braucht auch die Gruppe Vorlagen.
  Result := ServerMenu(ASession, ASpot, mMenu);
  if not Result then
  begin
    Exit;
  end;
  // slashCommands aus: keine Schnellbefehle, Vorlagen und Code-Aktionen bleiben.
  if mMenu.Enabled then
  begin
    AContent.Entries := mMenu.Entries;
  end;
  if AOptions.HasGroup(TAtlasGenerateGroup.Generate) then
  begin
    AContent.Actions := RefactorActions(ASession, AFileName, ARange);
    AContent.Entries := AContent.Entries + TAtlasGenerateProtocol.FromActions(AContent.Actions);
  end;
  if AOptions.HasGroup(TAtlasGenerateGroup.Templates) and Assigned(TAtlasIdeGenerate.FSnippets) then
  begin
    AContent.Snippets := TAtlasIdeGenerate.FSnippets();
    AContent.Entries := AContent.Entries + TAtlasGenerateProtocol.FromSnippets(AContent.Snippets, mMenu.Places);
  end;
end;

/// <summary>Auswahl-Liste eines Eintrags über atlas.server.slashChoices; nil ohne Server oder Antwort.</summary>
function ChoicesFor(const ASpot: TAtlasGenerateSpot): TAtlasGenerateChoicesFunc;
begin
  Result :=
    function(const AEntry: TAtlasGenerateEntry): TArray<string>
    var
      mCurrent: TLspSession;
      mFound: TJSONValue;
    begin
      Result := nil;
      mCurrent := TAtlasIdeGenerate.Session;
      if mCurrent = nil then
      begin
        Exit;
      end;
      try
        mFound := mCurrent.RunCommand(TAtlasGenerateProtocol.cChoicesCommand,
          TAtlasGenerateProtocol.ChoicesArguments(ASpot, AEntry.Name), cCommandTimeoutMs);
      except
        on E: ELspClientError do
        begin
          TAtlasGuard.Log('Erzeugen-Menü: Auswahl fehlt (' + TAtlasGuard.MessageText(E.Message) + ')');
          Exit;
        end;
      end;
      try
        Result := TAtlasGenerateProtocol.ParseChoices(mFound);
      finally
        mFound.Free;
      end;
    end;
end;

/// <summary>Eintrag ausblenden: keys.generateMenu.hidden speichern.</summary>
procedure HideEntry(const AEntry: TAtlasGenerateEntry);
var
  mNext: TAtlasPluginSettings;
begin
  mNext := TAtlasIdeSettings.Stored;
  mNext.GenerateMenuHidden := TAtlasGenerateOptions.AddHidden(mNext.GenerateMenuHidden, AEntry.Id);
  TAtlasIdeSettings.Update(mNext);
  TAtlasIdeGenerate.Say(TAtlasGenerateStrings.Fmt(TAtlasGenerateTextId.GenerateHiddenSaved, [AEntry.Caption]));
end;

/// <summary>Gewählten Eintrag ausführen: Schnellbefehl, Vorlage oder Code-Aktion.</summary>
procedure ExecuteEntry(const AView: IOTAEditView; const ASpot: TAtlasGenerateSpot; const AContent: TMenuContent;
  const AEntry: TAtlasGenerateEntry; const AArgument: string);
var
  mCurrent: TLspSession;
begin
  if (AView = nil) or (AView.Buffer = nil) then
  begin
    Exit;
  end;
  TAtlasIdeGenerate.Remember(AEntry);
  case AEntry.Kind of
    TAtlasGenerateKind.Slash:
      begin
        mCurrent := TAtlasIdeGenerate.Session;
        if mCurrent = nil then
        begin
          TAtlasIdeGenerate.Say(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
          Exit;
        end;
        RunSlash(AView, mCurrent, ASpot, AEntry, AArgument,
          procedure(AText: string)
          begin
            TAtlasIdeGenerate.Say(AText);
          end);
      end;
    TAtlasGenerateKind.Snippet:
      if Assigned(TAtlasIdeGenerate.FInsertSnippet) and (AEntry.Source >= 0) and
        (AEntry.Source <= High(AContent.Snippets)) then
      begin
        TAtlasIdeGenerate.FInsertSnippet(AView, AContent.Snippets[AEntry.Source]);
      end;
  else
    if Assigned(TAtlasIdeGenerate.FApplyAction) and (AEntry.Source >= 0) and
      (AEntry.Source <= High(AContent.Actions)) then
    begin
      TAtlasIdeGenerate.FApplyAction(AContent.Actions[AEntry.Source]);
    end;
  end;
end;

/// <summary>Ausführen erst nach dem Schließen des Fensters, abgesichert über die Funktion Erzeugen.</summary>
function ExecuteFor(const AView: IOTAEditView; const ASpot: TAtlasGenerateSpot; const AContent: TMenuContent):
  TAtlasGenerateExecuteProc;
begin
  Result :=
    procedure(const AEntry: TAtlasGenerateEntry; const AArgument: string)
    var
      mEntry: TAtlasGenerateEntry;
      mArgument: string;
    begin
      mEntry := AEntry;
      mArgument := AArgument;
      TAtlasGuard.Run(TAtlasFeature.Generate,
        procedure
        begin
          ExecuteEntry(AView, ASpot, AContent, mEntry, mArgument);
        end);
    end;
end;

/// <summary>Am Caret zeigen; ohne Caret über dem Hauptfenster bzw. dem Arbeitsbereich.</summary>
procedure ShowMenuWindow(AWindow: TAtlasGenerateWindow);
var
  mCaret, mArea: TRect;
begin
  if CaretRect(mCaret) then
  begin
    AWindow.ShowAt(mCaret);
    Exit;
  end;
  mArea := Screen.WorkAreaRect;
  if Application.MainForm <> nil then
  begin
    mArea := Application.MainForm.BoundsRect;
  end;
  AWindow.ShowOver(mArea);
end;

class procedure TAtlasIdeGenerate.Show(const AGroups: TArray<TAtlasGenerateGroup>);
var
  mView: IOTAEditView;
  mRunning: TLspSession;
  mText: string;
  mSpot: TAtlasGenerateSpot;
  mRange: TLspRange;
  mOptions: TAtlasGenerateOptions;
  mContent: TMenuContent;
  mIndex: Integer;
  mWindow: TAtlasGenerateWindow;
  mCollected: Boolean;
begin
  if not ReadyToShow(mView, mRunning) then
  begin
    Exit;
  end;
  mText := TAtlasEditorBuffer.Text(mView.Buffer);
  mRunning.Sync(mView.Buffer.FileName, mText);
  SpotOf(mView, TTextLines.SplitLines(mText), TAtlasEditorBuffer.TabWidth(mView.Buffer), mSpot, mRange);
  mOptions := MenuOptions(AGroups);
  Screen.Cursor := crHourGlass;
  try
    mCollected := CollectMenu(mRunning, mView.Buffer.FileName, mSpot, mRange, mOptions, mContent);
  finally
    Screen.Cursor := crDefault;
  end;
  if not mCollected then
  begin
    Exit;
  end;
  // Beschriftungen in der Sprache der Oberfläche; filtert das Fenster mit.
  for mIndex := 0 to High(mContent.Entries) do
  begin
    mContent.Entries[mIndex].Caption := TAtlasGenerateTexts.EntryCaption(mContent.Entries[mIndex]);
  end;
  LoadRecent;
  mWindow := TAtlasGenerateWindow.CreateMenu(Application, mContent.Entries, mOptions, FRecent, TAtlasIdeStyle.Colors);
  mWindow.OnChoices := ChoicesFor(mSpot);
  mWindow.OnHide := HideEntry;
  mWindow.OnExecute := ExecuteFor(mView, mSpot, mContent);
  ShowMenuWindow(mWindow);
end;

end.
