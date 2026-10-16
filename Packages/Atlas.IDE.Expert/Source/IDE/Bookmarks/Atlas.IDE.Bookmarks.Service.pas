unit Atlas.IDE.Bookmarks.Service;

// Benannte Lesezeichen (#622), IDE-Seite: hält je Projekt die Liste
// (TAtlasBookmarkList) im Speicher, liest und schreibt sie neben der .dproj
// (TAtlasBookmarks: lokal .atlas-bookmarks.json, mit bookmarks.shared
// atlas-bookmarks.json für das Team) und führt die Befehle aus:
// - „Lesezeichen setzen…“ (Strg+Alt+K, Menü Atlas, Kontextmenü, Palette):
//   kleiner Dialog mit Namensvorschlag (Methode und Zeilenbeginn) für die
//   Zeile, die zuletzt per Rechtsklick in der Rinne gewählt wurde
//   (TAtlasIdeGutterMarks.TakeLine), sonst für die Cursorzeile.
// - „Gehe zu Lesezeichen…“: alle Lesezeichen des Projekts in einem Fenster
//   wie die Befehlspalette mit unscharfer Suche über Name sowie Datei und
//   Methode (TAtlasCommandPalette), in der Reihenfolge der Liste.
// - „Lesezeichen-Fenster“: andockbares Seitenfenster (TAtlasIdeBookmarksWindow)
//   mit Filter, Sprung, Umbenennen (F2), Löschen (Entf) und Umsortieren.
// Vor dem Zeigen und vor jedem Sprung werden die Lesezeichen gegen den
// aktuellen Text wiedergefunden (offener Puffer, sonst Platte; fehlende
// Datei = „nicht gefunden“); Track tut das für die Datei im oberen Editor
// nach jeder Tipp-Pause, damit die Lesezeichen Änderungen folgen. Das Projekt
// einer Datei ist das Projekt der Projektgruppe, das sie enthält, sonst das
// aktive Projekt. Mit bookmarks.named aus ruht alles; die nummerierten
// Lesezeichen der IDE bleiben unberührt. Meldungen nur als Zeile in der
// Meldungsansicht. Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Bookmarks.Store,
  Atlas.UI.Bookmarks.Frame;

type
  TAtlasIdeBookmarks = class
  private class var
    FLists: TDictionary<string, TAtlasBookmarkList>;
    /// <summary>Datei (klein) → Projekt; gefüllt von Track und den Befehlen.</summary>
    FProjectOf: TDictionary<string, string>;
    FMessage: TProc<string>;
    /// <summary>Ablage, aus der die Listen im Speicher stammen (bookmarks.shared).</summary>
    FShared: Boolean;
    /// <summary>Projekt, dessen Lesezeichen das Seitenfenster zeigt.</summary>
    FWindowProject: string;
  private
    class function Key(const APath: string): string; static;
    class procedure Say(const AText: string); static;
    class function NowUtc: TDateTime; static;
    class function Enabled(AReport: Boolean): Boolean; static;
    class function ActiveProject: string; static;
    class function ResolveProject(const AFileName: string): string; static;
    /// <summary>Projekt der Datei im oberen Editor, sonst das aktive Projekt.</summary>
    class function CurrentProject: string; static;
    class procedure CheckStorage; static;
    class function List(const AProject: string): TAtlasBookmarkList; static;
    class procedure Put(const AList: TAtlasBookmarkList); static;
    class function Store(const AList: TAtlasBookmarkList): Boolean; static;
    /// <summary>Alle Lesezeichen der Liste gegen den aktuellen Text wiederfinden; True bei Änderung.</summary>
    class function RelocateAll(var AList: TAtlasBookmarkList): Boolean; static;
    /// <summary>Lesezeichen einer Datei wiederfinden; True bei Änderung.</summary>
    class function RelocateFile(var AList: TAtlasBookmarkList; const AFileName: string): Boolean; static;
    /// <summary>Datei und Zeile (0-basiert) für „Lesezeichen setzen…“; False mit Meldung.</summary>
    class function Target(out AFileName: string; out ALine: Integer): Boolean; static;
    class function PlaceText(const AProject: string): string; static;
    class procedure WireFrame(AFrame: TAtlasBookmarksFrame); static;
    class procedure RefreshWindow(const ASelectId: string); static;
    class procedure Invalidate; static;
  public
    /// <summary>AMessage: Zeile für die Meldungsansicht.</summary>
    class procedure Start(const AMessage: TProc<string>); static;
    class procedure Release; static;
    /// <summary>Einstellungen geändert: Ablage gewechselt (neu lesen), ausgeschaltet (Fenster schließen).</summary>
    class procedure ApplySettings; static;
    class procedure ThemeChanged; static;
    /// <summary>Oberer Editor zeigt AFileName mit AText: Projekt merken, dessen Lesezeichen der Datei
    /// wiederfinden (gespeichert, wenn sich etwas ändert). True, wenn sich Lesezeichen geändert haben.</summary>
    class function Track(const AFileName, AText: string): Boolean; static;
    /// <summary>Hat AFileName Lesezeichen (aus dem Speicher, ohne IDE-Aufrufe; erst nach Track bekannt)?</summary>
    class function HasBookmarks(const AFileName: string): Boolean; static;
    /// <summary>Gefundene Lesezeichen an ALine (0-basiert); ohne IDE-Aufrufe, zum Zeichnen.</summary>
    class function BookmarksAt(const AFileName: string; ALine: Integer): TArray<TAtlasBookmark>; static;
    /// <summary>„Lesezeichen setzen…“.</summary>
    class procedure AddBookmark; static;
    /// <summary>„Gehe zu Lesezeichen…“.</summary>
    class procedure GoToBookmark; static;
    /// <summary>Seitenfenster „Lesezeichen“ zeigen.</summary>
    class procedure ShowWindow; static;
    /// <summary>Zum Lesezeichen AId von AProject springen (nicht gefunden: letzte bekannte Stelle).</summary>
    class procedure OpenBookmark(const AProject, AId: string); static;
    class procedure RenameBookmark(const AProject, AId, AName: string); static;
    class procedure DeleteBookmark(const AProject, AId: string); static;
    class procedure MoveBookmark(const AProject, AId, ABeforeId: string); static;
  end;

implementation

uses
  Atlas.IDE.Editor.Buffer,
  System.Types,
  System.DateUtils,
  System.UITypes,
  Vcl.Forms,
  Vcl.Dialogs,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Commands.Palette,
  Atlas.UI.Strings,
  Atlas.UI.Commands.Palette,
  Atlas.UI.Bookmarks.Dialog,
  Atlas.IDE.Editor.Style,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Editor.GutterMarks,
  Atlas.IDE.Results.Commands,
  Atlas.IDE.Bookmarks.Window,
  Atlas.IDE.Settings.Store;

{ TAtlasIdeBookmarks }

class procedure TAtlasIdeBookmarks.Start(const AMessage: TProc<string>);
begin
  // Mehrfach aufgerufen (nach jeder Einstellungsänderung): vorhandene Listen bleiben, ApplySettings wechselt
  // bei Bedarf die Ablage.
  FMessage := AMessage;
  if FLists = nil then
  begin
    FLists := TDictionary<string, TAtlasBookmarkList>.Create;
    FShared := TAtlasIdeSettings.Current.BookmarksShared;
  end;
  if FProjectOf = nil then
    FProjectOf := TDictionary<string, string>.Create;
  TAtlasIdeBookmarksWindow.OnFrame :=
    procedure(AFrame: TAtlasBookmarksFrame)
    begin
      WireFrame(AFrame);
      RefreshWindow('');
    end;
end;

class procedure TAtlasIdeBookmarks.Release;
begin
  TAtlasIdeBookmarksWindow.Release;
  FMessage := nil;
  FreeAndNil(FLists);
  FreeAndNil(FProjectOf);
  FWindowProject := '';
end;

class function TAtlasIdeBookmarks.Key(const APath: string): string;
begin
  Result := LowerCase(Trim(APath)).Replace('/', '\');
end;

class procedure TAtlasIdeBookmarks.Say(const AText: string);
begin
  if Assigned(FMessage) then
    FMessage(AText);
end;

class function TAtlasIdeBookmarks.NowUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

class function TAtlasIdeBookmarks.Enabled(AReport: Boolean): Boolean;
begin
  Result := (FLists <> nil) and TAtlasIdeSettings.Current.BookmarksNamed;
  if not Result and AReport and (FLists <> nil) then
    Say(TAtlasStrings.Text(TAtlasTextId.BookmarksDisabled));
end;

class function TAtlasIdeBookmarks.ActiveProject: string;
var
  Services: IOTAModuleServices;
  Project: IOTAProject;
begin
  Result := '';
  if not Supports(BorlandIDEServices, IOTAModuleServices, Services) then
    Exit;
  Project := Services.GetActiveProject;
  if Project <> nil then
    Result := Project.FileName;
end;

class function TAtlasIdeBookmarks.ResolveProject(const AFileName: string): string;
begin
  Result := TAtlasIdeWorkspaceEdit.ProjectOfFile(AFileName);
  if Result = '' then
    Result := ActiveProject;
  if (Result <> '') and (FProjectOf <> nil) then
    FProjectOf.AddOrSetValue(Key(AFileName), Result);
end;

class function TAtlasIdeBookmarks.CurrentProject: string;
var
  View: IOTAEditView;
begin
  Result := '';
  // Auch aus Palette und Menü, wenn der Fokus nicht im Editor liegt.
  View := TAtlasEditorBuffer.ActiveView;
  if (View <> nil) and (View.Buffer <> nil) and (View.Buffer.FileName <> '') then
    Result := ResolveProject(View.Buffer.FileName);
  if Result = '' then
    Result := ActiveProject;
end;

class procedure TAtlasIdeBookmarks.CheckStorage;
begin
  // Ablage umgeschaltet: Listen aus der jeweils gültigen Datei neu lesen.
  if (FLists <> nil) and (FShared <> TAtlasIdeSettings.Current.BookmarksShared) then
  begin
    FLists.Clear;
    FShared := TAtlasIdeSettings.Current.BookmarksShared;
  end;
end;

class function TAtlasIdeBookmarks.List(const AProject: string): TAtlasBookmarkList;
begin
  CheckStorage;
  if (FLists <> nil) and FLists.TryGetValue(Key(AProject), Result) then
    Exit;
  // Ohne Datei oder bei ungültigem Inhalt: leere Liste zu diesem Projekt.
  TAtlasBookmarks.Load(AProject, FShared, Result);
  if FLists <> nil then
    FLists.AddOrSetValue(Key(AProject), Result);
end;

class procedure TAtlasIdeBookmarks.Put(const AList: TAtlasBookmarkList);
begin
  if FLists <> nil then
    FLists.AddOrSetValue(Key(AList.Project), AList);
end;

class function TAtlasIdeBookmarks.Store(const AList: TAtlasBookmarkList): Boolean;
begin
  Put(AList);
  Result := TAtlasBookmarks.Save(AList, FShared);
  if not Result then
    Say(TAtlasStrings.Text(TAtlasTextId.BookmarksSaveFailed));
end;

class function TAtlasIdeBookmarks.RelocateFile(var AList: TAtlasBookmarkList; const AFileName: string): Boolean;
var
  Text: string;
begin
  Text := TAtlasIdeWorkspaceEdit.CurrentText(AFileName);
  // Leer heißt: Datei fehlt (oder ist leer); ihre Lesezeichen sind dann nicht zu finden.
  if Text = '' then
    Result := AList.LoseFile(AFileName)
  else
    Result := AList.Relocate(AFileName, Text);
  if FProjectOf <> nil then
    FProjectOf.AddOrSetValue(Key(AFileName), AList.Project);
end;

class function TAtlasIdeBookmarks.RelocateAll(var AList: TAtlasBookmarkList): Boolean;
var
  FileName: string;
begin
  Result := False;
  for FileName in AList.Files do
    Result := RelocateFile(AList, FileName) or Result;
end;

class procedure TAtlasIdeBookmarks.Invalidate;
begin
  TAtlasIdeGutterMarks.Invalidate;
end;

class function TAtlasIdeBookmarks.Track(const AFileName, AText: string): Boolean;
var
  Project: string;
  Current: TAtlasBookmarkList;
begin
  Result := False;
  if not Enabled(False) or (AFileName = '') then
    Exit;
  Project := ResolveProject(AFileName);
  if Project = '' then
    Exit;
  // Das Seitenfenster folgt dem Projekt der Datei vorn.
  if TAtlasIdeBookmarksWindow.Visible and (Key(Project) <> Key(FWindowProject)) then
  begin
    FWindowProject := Project;
    RefreshWindow('');
  end;
  Current := List(Project);
  if Length(Current.ForFile(AFileName)) = 0 then
    Exit;
  Result := Current.Relocate(AFileName, AText);
  if not Result then
    Exit;
  Store(Current);
  RefreshWindow('');
end;

class function TAtlasIdeBookmarks.HasBookmarks(const AFileName: string): Boolean;
var
  Project: string;
  Current: TAtlasBookmarkList;
begin
  Result := (FProjectOf <> nil) and FProjectOf.TryGetValue(Key(AFileName), Project) and
    FLists.TryGetValue(Key(Project), Current) and (Length(Current.ForFile(AFileName)) > 0);
end;

class function TAtlasIdeBookmarks.BookmarksAt(const AFileName: string; ALine: Integer): TArray<TAtlasBookmark>;
var
  Project: string;
  Current: TAtlasBookmarkList;
begin
  Result := nil;
  if (FProjectOf <> nil) and FProjectOf.TryGetValue(Key(AFileName), Project) and
    FLists.TryGetValue(Key(Project), Current) then
    Result := Current.AtLine(AFileName, ALine);
end;

class function TAtlasIdeBookmarks.Target(out AFileName: string; out ALine: Integer): Boolean;
var
  View: IOTAEditView;
begin
  AFileName := '';
  ALine := -1;
  Result := False;
  if not Enabled(True) then
    Exit;
  // Auch aus Palette und Menü, wenn der Fokus nicht im Editor liegt.
  View := TAtlasEditorBuffer.ActiveView;
  if (View = nil) or (View.Buffer = nil) or (View.Buffer.FileName = '') then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.BookmarksNoEditor));
    Exit;
  end;
  AFileName := View.Buffer.FileName;
  // Rechtsklick in die Rinne gilt vor dem Cursor, solange er frisch ist und zur Datei passt.
  if not TAtlasIdeGutterMarks.TakeLine(AFileName, ALine) then
    ALine := View.CursorPos.Line - 1;
  Result := ALine >= 0;
end;

class procedure TAtlasIdeBookmarks.AddBookmark;
var
  FileName, Project, Text, Name, Id: string;
  Line: Integer;
  Current: TAtlasBookmarkList;
begin
  if not Target(FileName, Line) then
    Exit;
  Project := ResolveProject(FileName);
  if Project = '' then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.BookmarksNoProject));
    Exit;
  end;
  Text := TAtlasIdeWorkspaceEdit.CurrentText(FileName);
  Current := List(Project);
  // Erst wiederfinden, damit die übrigen Lesezeichen der Datei zum Text passen.
  Current.Relocate(FileName, Text);
  Name := TAtlasBookmarks.SuggestName(FileName, Text, Line);
  if not TAtlasBookmarkDialog.Execute(TAtlasStrings.Fmt(TAtlasTextId.BookmarksDialogTitle,
    [ExtractFileName(FileName), Line + 1]), Name) then
  begin
    // Abbrechen: nur das Wiederfinden behalten.
    Put(Current);
    Exit;
  end;
  Id := Current.Add(FileName, Text, Line, Name, NowUtc);
  Store(Current);
  Invalidate;
  if TAtlasIdeBookmarksWindow.Visible then
    FWindowProject := Project;
  RefreshWindow(Id);
end;

class procedure TAtlasIdeBookmarks.GoToBookmark;
var
  Project: string;
  Current: TAtlasBookmarkList;
  Commands: TArray<TAtlasCommand>;
  Command: TAtlasCommand;
  Mark: TAtlasBookmark;
  Window: TAtlasPaletteWindow;
  Area: TRect;
begin
  if not Enabled(True) then
    Exit;
  Project := CurrentProject;
  if Project = '' then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.BookmarksNoProject));
    Exit;
  end;
  Current := List(Project);
  if RelocateAll(Current) then
    Store(Current)
  else
    Put(Current);
  if Current.Count = 0 then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.BookmarksNone));
    Exit;
  end;
  // Name als Beschriftung, Ort (Datei, Zeile, Methode) als Pfad: Die Suche findet beides.
  Commands := nil;
  for Mark in Current.Bookmarks do
  begin
    Command := Default(TAtlasCommand);
    Command.Id := Mark.Id;
    Command.Caption := Mark.Name;
    Command.Path := TAtlasBookmarks.Location(Mark);
    if Mark.Lost then
      Command.ShortCut := TAtlasStrings.Text(TAtlasTextId.BookmarksLost);
    Command.Description := Mark.Preview;
    Commands := Commands + [Command];
  end;
  Window := TAtlasPaletteWindow.CreatePalette(Application, Commands, nil, TAtlasIdeStyle.Colors);
  Window.KeepOrder := True;
  Window.OnExecute :=
    procedure(ACommand: TAtlasCommand)
    var
      Id: string;
    begin
      Id := ACommand.Id;
      TAtlasGuard.Run(TAtlasFeature.Bookmarks,
        procedure
        begin
          OpenBookmark(Project, Id);
        end);
    end;
  if Screen.ActiveForm <> nil then
    Area := Screen.ActiveForm.BoundsRect
  else if Application.MainForm <> nil then
    Area := Application.MainForm.BoundsRect
  else
    Area := Screen.WorkAreaRect;
  Window.ShowOver(Area);
end;

class function TAtlasIdeBookmarks.PlaceText(const AProject: string): string;
var
  Current: TAtlasBookmarkList;
begin
  if AProject = '' then
    Exit(TAtlasStrings.Text(TAtlasTextId.BookmarksNoProjectList));
  // Fußzeile: „Lesezeichen in Projekt.dproj: 5, davon 1 nicht gefunden · Lokal in …“.
  Current := List(AProject);
  Result := TAtlasStrings.Fmt(TAtlasTextId.BookmarksListTitle,
    [ExtractFileName(AProject), Current.Count, Current.LostCount]) + ' · ';
  if FShared then
    Result := Result + TAtlasStrings.Text(TAtlasTextId.BookmarksStoredShared)
  else
    Result := Result + TAtlasStrings.Text(TAtlasTextId.BookmarksStoredLocal);
end;

class procedure TAtlasIdeBookmarks.WireFrame(AFrame: TAtlasBookmarksFrame);
begin
  if AFrame = nil then
    Exit;
  AFrame.OnOpen :=
    procedure(AId: string)
    begin
      TAtlasGuard.Run(TAtlasFeature.Bookmarks,
        procedure
        begin
          OpenBookmark(FWindowProject, AId);
        end);
    end;
  AFrame.OnRename :=
    procedure(AId, AName: string)
    begin
      TAtlasGuard.Run(TAtlasFeature.Bookmarks,
        procedure
        begin
          RenameBookmark(FWindowProject, AId, AName);
        end);
    end;
  AFrame.OnDelete :=
    procedure(AId: string)
    begin
      TAtlasGuard.Run(TAtlasFeature.Bookmarks,
        procedure
        begin
          DeleteBookmark(FWindowProject, AId);
        end);
    end;
  AFrame.OnMove :=
    procedure(AId, ABeforeId: string)
    begin
      TAtlasGuard.Run(TAtlasFeature.Bookmarks,
        procedure
        begin
          MoveBookmark(FWindowProject, AId, ABeforeId);
        end);
    end;
end;

class procedure TAtlasIdeBookmarks.RefreshWindow(const ASelectId: string);
var
  Frame: TAtlasBookmarksFrame;
  Current: TAtlasBookmarkList;
begin
  Frame := TAtlasIdeBookmarksWindow.ExistingFrame;
  if (Frame = nil) or (FLists = nil) then
    Exit;
  if FWindowProject = '' then
    Current := TAtlasBookmarkList.Create('')
  else
    Current := List(FWindowProject);
  Frame.SetBookmarks(Current, PlaceText(FWindowProject), ASelectId);
end;

class procedure TAtlasIdeBookmarks.ShowWindow;
var
  Current: TAtlasBookmarkList;
  Frame: TAtlasBookmarksFrame;
begin
  if not Enabled(True) then
    Exit;
  FWindowProject := CurrentProject;
  if FWindowProject <> '' then
  begin
    Current := List(FWindowProject);
    if RelocateAll(Current) then
      Store(Current)
    else
      Put(Current);
  end;
  Frame := TAtlasIdeBookmarksWindow.Show;
  if Frame = nil then
    Exit;
  RefreshWindow('');
  if Frame.Filter.CanFocus then
    Frame.Filter.SetFocus;
end;

class procedure TAtlasIdeBookmarks.OpenBookmark(const AProject, AId: string);
var
  Current: TAtlasBookmarkList;
  Index: Integer;
  Mark: TAtlasBookmark;
begin
  if not Enabled(True) or (AProject = '') then
    Exit;
  Current := List(AProject);
  Index := Current.IndexOf(AId);
  if Index < 0 then
    Exit;
  // Unmittelbar vor dem Sprung wiederfinden: Die Datei kann sich außerhalb geändert haben.
  if RelocateFile(Current, Current.Bookmarks[Index].FileName) then
  begin
    Store(Current);
    RefreshWindow(AId);
  end
  else
    Put(Current);
  Mark := Current.Bookmarks[Index];
  if Mark.Lost then
    Say(TAtlasStrings.Fmt(TAtlasTextId.BookmarksLostJump, [Mark.Name]));
  TAtlasIdeResults.Open(Mark.FileName, Mark.Line, 0);
  Invalidate;
end;

class procedure TAtlasIdeBookmarks.RenameBookmark(const AProject, AId, AName: string);
var
  Current: TAtlasBookmarkList;
begin
  if not Enabled(True) or (AProject = '') then
    Exit;
  Current := List(AProject);
  if not Current.Rename(AId, AName) then
    Exit;
  Store(Current);
  RefreshWindow(AId);
end;

class procedure TAtlasIdeBookmarks.DeleteBookmark(const AProject, AId: string);
var
  Current: TAtlasBookmarkList;
  Index: Integer;
begin
  if not Enabled(True) or (AProject = '') then
    Exit;
  Current := List(AProject);
  Index := Current.IndexOf(AId);
  if Index < 0 then
    Exit;
  if MessageDlg(TAtlasStrings.Fmt(TAtlasTextId.BookmarksDeleteConfirm, [Current.Bookmarks[Index].Name]),
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;
  Current.Remove(AId);
  Store(Current);
  Invalidate;
  RefreshWindow('');
end;

class procedure TAtlasIdeBookmarks.MoveBookmark(const AProject, AId, ABeforeId: string);
var
  Current: TAtlasBookmarkList;
begin
  if not Enabled(True) or (AProject = '') then
    Exit;
  Current := List(AProject);
  if not Current.MoveBefore(AId, ABeforeId) then
    Exit;
  Store(Current);
  RefreshWindow(AId);
end;

class procedure TAtlasIdeBookmarks.ApplySettings;
begin
  if FLists = nil then
    Exit;
  if not TAtlasIdeSettings.Current.BookmarksNamed then
  begin
    // Ausgeschaltet: Fenster zu, die Rinne zeichnet nichts mehr (Wanted der Schicht).
    TAtlasIdeBookmarksWindow.Hide;
    Invalidate;
    Exit;
  end;
  if FShared <> TAtlasIdeSettings.Current.BookmarksShared then
  begin
    CheckStorage;
    FProjectOf.Clear;
    Invalidate;
    RefreshWindow('');
  end;
end;

class procedure TAtlasIdeBookmarks.ThemeChanged;
begin
  TAtlasIdeBookmarksWindow.ApplyTheme;
end;

end.
