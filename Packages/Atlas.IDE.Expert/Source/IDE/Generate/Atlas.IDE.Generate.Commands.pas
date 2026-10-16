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
    FRecent: TAtlasGenerateRecent;
    FRecentLoaded: Boolean;
  private
    class function Session: TLspSession; static;
    class procedure Say(const AText: string); static;
    class procedure LoadRecent; static;
    class procedure Remember(const AEntry: TAtlasGenerateEntry); static;
  public
    /// <summary>ASessionOf: laufende Sitzung oder nil; AMessage: Zeile für die Meldungsansicht; ASnippets: alle
    /// Code-Vorlagen der Vervollständigung (leer, wenn sie aus sind); AInsertSnippet setzt eine Vorlage mit
    /// Platzhaltern am Cursor ein.</summary>
    class procedure Install(const ASessionOf: TFunc<TLspSession>; const AMessage: TProc<string>;
      const ASnippets: TFunc<TAtlasSnippetList>; const AInsertSnippet: TProc<IOTAEditView, TAtlasSnippet>); static;
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
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Generate.Protocol,
  Atlas.UI.Strings,
  Atlas.UI.Generate.Window,
  Atlas.IDE.Editor.Buffer,
  Atlas.IDE.Editor.Style,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Settings.Store,
  Atlas.IDE.Commands.Editor,
  Atlas.Core.Editor.WorkspacePlan;

const
  // Wie die Code-Aktionen: Der Server darf etwas rechnen (Vorfahren, Index).
  CommandTimeoutMs = 30000;

function LineAt(const ALines: TArray<string>; AIndex: Integer): string;
begin
  Result := '';
  if (AIndex >= 0) and (AIndex < Length(ALines)) then
    Result := ALines[AIndex];
end;

/// <summary>Caret des Editors in Bildschirmkoordinaten; False ohne Caret.</summary>
function CaretRect(out ARect: TRect): Boolean;
var
  Info: TGUIThreadInfo;
begin
  FillChar(Info, SizeOf(Info), 0);
  Info.cbSize := SizeOf(Info);
  Result := GetGUIThreadInfo(GetCurrentThreadId, Info) and (Info.hwndCaret <> 0);
  if not Result then
    Exit;
  ARect := Info.rcCaret;
  MapWindowPoints(Info.hwndCaret, 0, ARect, 2);
end;

{ TAtlasIdeGenerate }

class procedure TAtlasIdeGenerate.Install(const ASessionOf: TFunc<TLspSession>; const AMessage: TProc<string>;
  const ASnippets: TFunc<TAtlasSnippetList>; const AInsertSnippet: TProc<IOTAEditView, TAtlasSnippet>);
begin
  FSessionOf := ASessionOf;
  FMessage := AMessage;
  FSnippets := ASnippets;
  FInsertSnippet := AInsertSnippet;
  FRecent := TAtlasGenerateRecent.Create;
  FRecentLoaded := False;
end;

class procedure TAtlasIdeGenerate.Uninstall;
begin
  FreeAndNil(FRecent);
  FRecentLoaded := False;
  FSessionOf := nil;
  FMessage := nil;
  FSnippets := nil;
  FInsertSnippet := nil;
end;

class function TAtlasIdeGenerate.Session: TLspSession;
begin
  Result := nil;
  if Assigned(FSessionOf) then
    Result := FSessionOf();
end;

class procedure TAtlasIdeGenerate.Say(const AText: string);
begin
  if Assigned(FMessage) then
    FMessage(AText);
end;

class function TAtlasIdeGenerate.RecentFile: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('APPDATA'), 'Atlas'), 'generate-recent.txt');
end;

class procedure TAtlasIdeGenerate.LoadRecent;
begin
  if FRecentLoaded or (FRecent = nil) then
    Exit;
  FRecentLoaded := True;
  try
    if TFile.Exists(RecentFile) then
      FRecent.LoadFromText(TFile.ReadAllText(RecentFile, TEncoding.UTF8));
  except
    on E: Exception do
      // Ohne Pfad im Protokoll (#647); der Verlauf beginnt dann leer.
      TAtlasGuard.Log('Erzeugen-Menü: Verlauf nicht lesbar (' + E.ClassName + ')');
  end;
end;

class procedure TAtlasIdeGenerate.Remember(const AEntry: TAtlasGenerateEntry);
begin
  if FRecent = nil then
    Exit;
  LoadRecent;
  FRecent.Chosen(AEntry.Id);
  try
    ForceDirectories(ExtractFileDir(RecentFile));
    TFile.WriteAllText(RecentFile, FRecent.ToText, TEncoding.UTF8);
  except
    on E: Exception do
      TAtlasGuard.Log('Erzeugen-Menü: Verlauf nicht gespeichert (' + E.ClassName + ')');
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
  Block: IOTAEditBlock;
  Cursor: TOTAEditPos;
  StartLine, StartChar, EndLine, EndChar: Integer;
begin
  Cursor := AView.CursorPos;
  StartLine := Cursor.Line - 1;
  StartChar := TLspSession.ColumnToIndex(LineAt(ALines, StartLine), Cursor.Col, ATabWidth);
  ARange.StartPos := TLspTextPosition.Create(StartLine, StartChar);
  ARange.EndPos := ARange.StartPos;
  ASpot := TAtlasGenerateSpot.Create(TLspSession.PathToUri(AView.Buffer.FileName), StartLine, StartChar, -1);
  Block := AView.Block;
  if (Block = nil) or not Block.IsValid or (Block.Size = 0) then
    Exit;
  StartLine := Block.StartingRow - 1;
  StartChar := TLspSession.ColumnToIndex(LineAt(ALines, StartLine), Block.StartingColumn, ATabWidth);
  EndLine := Block.EndingRow - 1;
  EndChar := TLspSession.ColumnToIndex(LineAt(ALines, EndLine), Block.EndingColumn, ATabWidth);
  ARange.StartPos := TLspTextPosition.Create(StartLine, StartChar);
  ARange.EndPos := TLspTextPosition.Create(EndLine, EndChar);
  // Umschließen beginnt an der ersten Zeile der Markierung.
  ASpot := TAtlasGenerateSpot.Create(ASpot.Uri, StartLine, StartChar,
    TAtlasGenerateMenu.SelectionEndLine(StartLine, EndLine, EndChar, True));
end;

/// <summary>Führt einen Schnellbefehl über atlas.server.slashRun aus: ein Rückgängig-Schritt.</summary>
procedure RunSlash(const AView: IOTAEditView; ASession: TLspSession; const ASpot: TAtlasGenerateSpot;
  const AEntry: TAtlasGenerateEntry; const AArgument: string; const ASay: TProc<string>);
var
  FileName, Reason: string;
  Answer: TJSONValue;
  Edits: TArray<TLspTextEdit>;
  Edit: TLspWorkspaceEdit;
  Outcome: TAtlasWorkspaceEditResult;
  Done: Boolean;
begin
  FileName := AView.Buffer.FileName;
  ASession.Sync(FileName, TAtlasEditorBuffer.Text(AView.Buffer));
  try
    Answer := ASession.RunCommand(TAtlasGenerateProtocol.RunCommand,
      TAtlasGenerateProtocol.RunArguments(ASpot, AEntry.Name, AArgument), CommandTimeoutMs);
  except
    on E: ELspClientError do
    begin
      ASay(TAtlasStrings.Fmt(TAtlasTextId.GenerateFailed, [E.Message]));
      Exit;
    end;
  end;
  try
    Done := TAtlasGenerateProtocol.ParseRun(Answer, Edits, Reason);
  finally
    Answer.Free;
  end;
  if not Done then
  begin
    ASay(TAtlasStrings.Fmt(TAtlasTextId.GenerateFailed, [Reason]));
    Exit;
  end;
  Edit := Default(TLspWorkspaceEdit);
  Edit.Files := [Default(TLspFileEdits)];
  Edit.Files[0].FileName := FileName;
  Edit.Files[0].Edits := Edits;
  Outcome := TAtlasIdeWorkspaceEdit.Apply(Edit, TAtlasUnopenedPolicy.WriteToDisk,
    TAtlasGenerateWindow.EntryCaption(AEntry));
  if Outcome.Error <> '' then
    ASay(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [Outcome.Error]));
end;

class procedure TAtlasIdeGenerate.Show(const AGroups: TArray<TAtlasGenerateGroup>);
var
  Settings: TAtlasPluginSettings;
  Editors: IOTAEditorServices;
  View: IOTAEditView;
  Running: TLspSession;
  FileName, Text: string;
  Lines: TArray<string>;
  Spot: TAtlasGenerateSpot;
  Range: TLspRange;
  Options: TAtlasGenerateOptions;
  Answer: TJSONValue;
  Menu: TAtlasGenerateServerMenu;
  Actions: TArray<TLspCodeAction>;
  Snippets: TAtlasSnippetList;
  Entries: TArray<TAtlasGenerateEntry>;
  Index: Integer;
  Window: TAtlasGenerateWindow;
  Caret, Area: TRect;
begin
  Settings := TAtlasIdeSettings.Current;
  if not Settings.GenerateMenu then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.GenerateMenuOff));
    Exit;
  end;
  View := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
    View := Editors.TopView;
  if (View = nil) or (View.Buffer = nil) then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.ResultsNothing));
    Exit;
  end;
  Running := Session;
  if Running = nil then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  FileName := View.Buffer.FileName;
  Text := TAtlasEditorBuffer.Text(View.Buffer);
  Running.Sync(FileName, Text);
  Lines := TTextLines.SplitLines(Text);
  SpotOf(View, Lines, TAtlasEditorBuffer.TabWidth(View.Buffer), Spot, Range);
  Options := TAtlasGenerateOptions.Create(Settings.GenerateMenuGroups, Settings.GenerateMenuHidden,
    Settings.GenerateMenuRecentFirst, Settings.GenerateMenuShowCommandNames);
  if Length(AGroups) > 0 then
    Options := Options.Only(AGroups);
  Entries := nil;
  Actions := nil;
  Snippets := nil;
  Screen.Cursor := crHourGlass;
  try
    // Orte und Schnellbefehle; die Orte braucht auch die Gruppe Vorlagen.
    try
      Answer := Running.RunCommand(TAtlasGenerateProtocol.MenuCommand, TAtlasGenerateProtocol.MenuArguments(Spot),
        CommandTimeoutMs);
    except
      on E: ELspClientError do
      begin
        Say(TAtlasStrings.Fmt(TAtlasTextId.GenerateFailed, [E.Message]));
        Exit;
      end;
    end;
    try
      Menu := TAtlasGenerateProtocol.ParseMenu(Answer);
    finally
      Answer.Free;
    end;
    // slashCommands aus: keine Schnellbefehle, Vorlagen und Code-Aktionen bleiben.
    if Menu.Enabled then
      Entries := Menu.Entries;
    if Options.HasGroup(TAtlasGenerateGroup.Generate) then
    begin
      try
        Actions := Running.CodeActions(FileName, Range);
      except
        on E: ELspClientError do
        begin
          TAtlasGuard.Log('Erzeugen-Menü: Code-Aktionen fehlen (' + E.Message + ')');
          Actions := nil;
        end;
      end;
      Entries := Entries + TAtlasGenerateProtocol.FromActions(Actions);
    end;
    if Options.HasGroup(TAtlasGenerateGroup.Templates) and Assigned(FSnippets) then
    begin
      Snippets := FSnippets();
      Entries := Entries + TAtlasGenerateProtocol.FromSnippets(Snippets, Menu.Places);
    end;
  finally
    Screen.Cursor := crDefault;
  end;
  // Beschriftungen in der Sprache der Oberfläche; filtert das Fenster mit.
  for Index := 0 to High(Entries) do
    Entries[Index].Caption := TAtlasGenerateWindow.EntryCaption(Entries[Index]);
  LoadRecent;
  Window := TAtlasGenerateWindow.CreateMenu(Application, Entries, Options, FRecent, TAtlasIdeStyle.Colors);
  Window.OnChoices :=
    function(const AEntry: TAtlasGenerateEntry): TArray<string>
    var
      Current: TLspSession;
      Found: TJSONValue;
    begin
      Result := nil;
      Current := Session;
      if Current = nil then
        Exit;
      try
        Found := Current.RunCommand(TAtlasGenerateProtocol.ChoicesCommand,
          TAtlasGenerateProtocol.ChoicesArguments(Spot, AEntry.Name), CommandTimeoutMs);
      except
        on E: ELspClientError do
        begin
          TAtlasGuard.Log('Erzeugen-Menü: Auswahl fehlt (' + E.Message + ')');
          Exit;
        end;
      end;
      try
        Result := TAtlasGenerateProtocol.ParseChoices(Found);
      finally
        Found.Free;
      end;
    end;
  Window.OnHide :=
    procedure(const AEntry: TAtlasGenerateEntry)
    var
      Next: TAtlasPluginSettings;
    begin
      Next := TAtlasIdeSettings.Stored;
      Next.GenerateMenuHidden := TAtlasGenerateOptions.AddHidden(Next.GenerateMenuHidden, AEntry.Id);
      TAtlasIdeSettings.Update(Next);
      Say(TAtlasStrings.Fmt(TAtlasTextId.GenerateHiddenSaved, [AEntry.Caption]));
    end;
  Window.OnExecute :=
    procedure(const AEntry: TAtlasGenerateEntry; const AArgument: string)
    var
      Entry: TAtlasGenerateEntry;
      Argument: string;
    begin
      Entry := AEntry;
      Argument := AArgument;
      TAtlasGuard.Run(TAtlasFeature.EditorCommands,
        procedure
        var
          Current: TLspSession;
        begin
          if (View = nil) or (View.Buffer = nil) then
            Exit;
          Remember(Entry);
          case Entry.Kind of
            TAtlasGenerateKind.Slash:
              begin
                Current := Session;
                if Current = nil then
                begin
                  Say(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
                  Exit;
                end;
                RunSlash(View, Current, Spot, Entry, Argument,
                  procedure(AText: string)
                  begin
                    Say(AText);
                  end);
              end;
            TAtlasGenerateKind.Snippet:
              if Assigned(FInsertSnippet) and (Entry.Source >= 0) and (Entry.Source <= High(Snippets)) then
                FInsertSnippet(View, Snippets[Entry.Source]);
          else
            if (Entry.Source >= 0) and (Entry.Source <= High(Actions)) then
              TAtlasIdeEditorCommands.ApplyAction(Actions[Entry.Source]);
          end;
        end);
    end;
  if CaretRect(Caret) then
    Window.ShowAt(Caret)
  else
  begin
    if Application.MainForm <> nil then
      Area := Application.MainForm.BoundsRect
    else
      Area := Screen.WorkAreaRect;
    Window.ShowOver(Area);
  end;
end;

end.
