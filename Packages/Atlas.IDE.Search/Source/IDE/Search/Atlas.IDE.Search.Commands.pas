unit Atlas.IDE.Search.Commands;

// Atlas-Suche im Editor (#877, #878):
// - Show: Suchleiste (Atlas.UI.Search.Bar) am unteren Rand des obersten
//   Editorfensters (alBottom im Eltern-Steuerelement des Editors „Editor“, wie
//   die Brotkrumenleiste oben). Jedes Editorfenster bekommt beim ersten Öffnen
//   seine eigene Leiste. Vorschlag ist die einzeilige Markierung, sonst der
//   Bezeichner am Cursor, sonst die letzte Suche. Bereich ist immer die Unit
//   (mehrzeilige Markierung: Auswahl); ShowInMethod („In Methode suchen“,
//   #877) stellt ihn auf Methode und die Stufe auf die innerste Routine.
//   Sonst gilt Methode nur, wenn der Anwender sie in der Leiste wählt.
// - Jede Änderung in der Leiste sucht neu: Treffer im Editor gerahmt, Sprung
//   zum nächsten Treffer ab der Stelle, an der die Leiste geöffnet wurde,
//   Zähler „n von m“. Bei Bereich Auswahl und Methode gelten Auswahl und
//   Cursor beim Öffnen; die Auswahl wandert nicht mit den Treffern.
// - Enter bzw. „In Meldungen“ listet alle Treffer im Reiter „Atlas-Suche“ des
//   Fensters Meldungen (Atlas.IDE.Search.MessageList, search.resultsInMessages);
//   dieselbe Suche wird nicht erneut aufgebaut. Der Fokus bleibt in der Leiste.
// - TryNext (F3/Umschalt+F3, in der Leiste auch Enter/Umschalt+Enter):
//   nächster bzw. voriger Treffer der letzten Suche mit Umlauf (Meldung in
//   der Meldungsansicht), auch bei geschlossener Leiste. Ohne letzte Suche
//   False: die Taste geht weiter (Markierung suchen bzw. „Erneut suchen“ der
//   IDE). Ist ein anderer Text einzeilig markiert als zuletzt gesucht, sucht
//   F3 nach der Markierung. Bei Bereich Methode und Cursor außerhalb jeder
//   Routine sucht F3 in der ganzen Unit (Meldung).
// - Esc bzw. × schließt die Leiste, gibt den Fokus an den Editor zurück und
//   beendet die Hervorhebung; F3 sucht weiter mit der letzten Suche.
// - Solange die Leiste offen ist, prüft ein Takt (Probe): Holt die IDE den
//   Fokus kurz nach dem Klick in die Leiste wieder in den Editor, kommt er
//   einmal zurück; liegt über der Leiste ein anderes Fenster, wird sie nach
//   vorn geholt. Beides steht mit Fensterklasse im Diagnoseprotokoll, ebenso
//   beim ersten Öffnen je Fenster die Lage von Editor und Leiste.
// Ersetzen, Regex, Verlauf und Bereiche über Dateien (#893):
// - ShowReplace (Strg+H, search.replace) öffnet die Leiste mit Ersetzen-Zeile,
//   Show ohne. „Ersetzen“ ersetzt den markierten Treffer und springt weiter;
//   steht keiner markiert, springt es nur. „Alle ersetzen“ ersetzt im Bereich:
//   in einer Datei als ein Rückgängig-Schritt (Schreiber der IDE), über Dateien
//   über TAtlasIdeWorkspaceEdit mit dem Änderungsprotokoll (#721). Danach
//   steht „n Ersetzungen in m Dateien“ in der Leiste.
// - Regex (search.regex): ungültiger Ausdruck färbt das Suchfeld rot und zeigt
//   den Fehlertext; dann wird nichts markiert, gezählt oder ersetzt. Bei
//   offener Ersetzen-Zeile zeigt die Leiste die Vorschau des aktuellen
//   Treffers.
// - Bereiche „Offene Dateien“, „Projekt“, „Projektgruppe“ (search.multiFile):
//   Der Editor hebt nur die aktive Datei hervor; nach einer kurzen Pause im
//   Tippen sucht TAtlasIdeFileSearch im Hintergrund (Puffer vor Platte), der
//   Zähler zeigt „n Treffer in m Dateien“. Enter bzw. „In Meldungen“ listet
//   die Dateien nach und nach im Reiter „Atlas-Suche“; „Abbrechen“ beendet
//   die Suche. F3 springt über Dateien (aktive Datei mit ihrem aktuellen
//   Text). „Auswählen …“ zeigt die Treffer mit Häkchen im Fenster
//   „Atlas-Suche: Ersetzen“; „Ausgewählte ersetzen“ ändert nur angehakte,
//   schreibgeschützte und seit der Suche geänderte Dateien werden gemeldet und
//   übersprungen. „Alle ersetzen“ sucht vorher neu.
// - Verlauf (search.history): Such- und Ersetzen-Verlauf in
//   %APPDATA%\Atlas\search-history.json über Neustarts (TAtlasDataFile).
// Tasten: Strg+F/F3/Umschalt+F3 nur mit search.replaceIdeSearch, Strg+H
// zusätzlich nur mit search.replace (Atlas.IDE.Commands.Bindings), „In
// Methode suchen“ immer. Nur im Hauptthread.
// - Anlegen je Editorfenster (auf Abruf, EnsureFor), Wächter, Freigabe nach
//   der Sperre durch die IDE und Abbau übernimmt TAtlasEditorBarHost (#1248).
//   Die Leisten sind verborgen, bis Show sie öffnet; deshalb kein Guard.
// Aufteilung: Zustand in Atlas.IDE.Search.Session, Editorzugriff in .Editor, Rahmen der Treffer in .Painter,
// Zähler und Vorschau in .Counter, Suche über Dateien in .AcrossFiles, Sync/F3/Liste in .Stepping, Ersetzen in
// .Replacing, Verlauf in .HistoryFile. Diese Unit hält die Leisten, den Takt und die Befehle.

interface

uses
  System.SysUtils,
  System.Classes,
  Winapi.Windows,
  Vcl.Controls,
  Vcl.ExtCtrls,
  ToolsAPI,
  Atlas.UI.Search.Bar,
  Atlas.IDE.Foundation.EditorBarHost,
  Atlas.IDE.Search.Painter;

type
  TAtlasIdeSearch = class
  private type
    /// <summary>Besitzer der Takte bei offener Leiste.</summary>
    TProbeOwner = class(TComponent)
    public
      procedure Tick(Sender: TObject);
      procedure FilesTick(Sender: TObject);
    end;
  private class var
    FPainter: TAtlasIdeSearchPainter;
    FHost: TAtlasEditorBarHost;
    FProbeOwner: TProbeOwner;
    // Takt bei offener Leiste: Fokus und Fenster unter der Maus (Probe).
    FProbe: TTimer;
    FProbed: HWND;
    FEntered: TWinControl;
    FEnteredAt: UInt64;
  private
    class procedure CreateTimers; static;
    class procedure Open(AInMethod, AReplace: Boolean); static;
    class function Features: TAtlasSearchBarFeatures; static;
    class function BarFor(const AWindow: INTAEditWindow): TAtlasSearchBar; static;
    class function CreateBar: TAtlasSearchBar; static;
    class procedure Place(ABar: TAtlasSearchBar; AParent: TWinControl); static;
    class procedure Removed(ABar: TControl); static;
    class procedure ThemeBar(ABar: TAtlasSearchBar); static;
    class procedure BarStep(ABackward: Boolean); static;
    class procedure CloseBar; static;
    class procedure Probe; static;
    /// <summary>Kurz nach dem Klick in die Leiste wieder im Editor: Die IDE hat den Fokus zurückgeholt; einmal
    /// zurück.</summary>
    class procedure RestoreFocus(ABar: TAtlasSearchBar); static;
    /// <summary>Von der IDE gesperrte Leisten wieder freigeben (Projektwechsel).</summary>
    class procedure EnableBars; static;
    class procedure LogLayout(ABar: TAtlasSearchBar); static;
    class procedure StopProbe; static;
  public
    /// <summary>Zeichner anmelden; AMessage schreibt eine Zeile in die Meldungsansicht.</summary>
    class procedure Install(const AMessage: TProc<string>); static;
    class procedure Uninstall; static;
    /// <summary>search.resultsInMessages aus: Reiter entfernen und Schaltfläche ausblenden.</summary>
    class procedure ApplySettings; static;
    class procedure ThemeChanged; static;
    /// <summary>Suchleiste (Strg+F, Befehl Atlas.Search).</summary>
    class procedure Show; static;
    /// <summary>Suchleiste mit Bereich Methode (#877, Befehl Atlas.SearchInMethod).</summary>
    class procedure ShowInMethod; static;
    /// <summary>Suchleiste mit Ersetzen-Zeile (#893, Strg+H, Befehl Atlas.SearchReplace); mit search.replace aus
    /// wie Show.</summary>
    class procedure ShowReplace; static;
    /// <summary>F3/Umschalt+F3: False ohne letzte Atlas-Suche oder ohne Editor.</summary>
    class function TryNext(ABackward: Boolean): Boolean; static;
    /// <summary>Für Palette und Menü: wie TryNext, ohne letzte Suche öffnet sich die Leiste.</summary>
    class procedure FindNext; static;
    class procedure FindPrevious; static;
    class procedure ClearHighlights; static;
  end;

implementation

uses
  Vcl.Forms,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Search.Matching,
  Atlas.Core.Search.Scopes,
  Atlas.Core.Search.Results,
  Atlas.Text.Lines,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.DockWindow,
  Atlas.IDE.Search.MessageList,
  Atlas.IDE.Search.FileSearch,
  Atlas.IDE.Search.ReplaceWindow,
  Atlas.IDE.Search.HistoryFile,
  Atlas.IDE.Search.Editor,
  Atlas.IDE.Search.Session,
  Atlas.IDE.Search.Counter,
  Atlas.IDE.Search.AcrossFiles,
  Atlas.IDE.Search.Stepping,
  Atlas.IDE.Search.Replacing;

const
  // Takt bei offener Leiste und Frist, in der ein Fokusverlust nach dem Klick als zurückgeholt gilt.
  cProbeMs = 100;
  cFocusGraceMs = 400;
  // Pause im Tippen, nach der die Suche über Dateien beginnt (#893).
  cFilesDelayMs = 400;

/// <summary>Ereignis einer Leiste: nur für die Leiste der laufenden Suche, geschützt.</summary>
function Guarded(ABar: TAtlasSearchBar; const AProc: TProc): TProc;
begin
  Result :=
    procedure
    begin
      if ABar = TAtlasIdeSearchSession.Bar then
      begin
        TAtlasGuard.Run(TAtlasFeature.Search, AProc);
      end;
    end;
end;

function GuardedStep(ABar: TAtlasSearchBar; const AStep: TAtlasSearchBarStep): TAtlasSearchBarStep;
begin
  Result :=
    procedure(ABackward: Boolean)
    begin
      if ABar = TAtlasIdeSearchSession.Bar then
      begin
        TAtlasGuard.Run(TAtlasFeature.Search,
          procedure
          begin
            AStep(ABackward);
          end);
      end;
    end;
end;

function WindowName(AWindow: HWND): string;
var
  mWindowClass: array[0..255] of Char;
  mControl: TWinControl;
begin
  if AWindow = 0 then
  begin
    Exit('kein Fenster');
  end;
  mWindowClass[0] := #0;
  GetClassName(AWindow, mWindowClass, Length(mWindowClass));
  Result := string(mWindowClass);
  mControl := FindControl(AWindow);
  if mControl <> nil then
  begin
    Result := Result + ', ' + mControl.ClassName + ' ' + mControl.Name;
  end;
end;

/// <summary>Vorschlag: einzeilige Markierung, sonst Bezeichner am Cursor, sonst die letzte Suche.</summary>
function Proposal(const ALines: TArray<string>; const ACursor: TAtlasSearchPos; const ASelection: TAtlasSearchArea;
  AHasSelection: Boolean): string;
begin
  Result := TAtlasIdeSearchEditor.LineSelection(ALines, ASelection, AHasSelection);
  if (Result = '') and (ACursor.Line >= 0) and (ACursor.Line <= High(ALines)) then
  begin
    Result := TAtlasTextSearch.WordAt(ALines[ACursor.Line], ACursor.Character);
  end;
  if Result = '' then
  begin
    Result := TAtlasIdeSearchSession.Last.Text;
  end;
end;

/// <summary>Stufen für „Methode“: die Routinen um den Cursor, innerste zuerst.</summary>
function Levels(const AText: string; const ACursor: TAtlasSearchPos): TArray<string>;
var
  mRoutine: TAtlasSearchRoutine;
begin
  Result := nil;
  for mRoutine in TAtlasSearchScopes.RoutinesAt(AText, ACursor) do
  begin
    Result := Result + [mRoutine.Caption];
  end;
end;

{ TAtlasIdeSearch.TProbeOwner }

procedure TAtlasIdeSearch.TProbeOwner.Tick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Search, TAtlasIdeSearch.Probe);
end;

procedure TAtlasIdeSearch.TProbeOwner.FilesTick(Sender: TObject);
begin
  TAtlasIdeSearchAcrossFiles.Tick;
end;

{ TAtlasIdeSearch }

class procedure TAtlasIdeSearch.Install(const AMessage: TProc<string>);
begin
  TAtlasIdeSearchSession.OnMessage := AMessage;
  if FPainter = nil then
  begin
    FPainter := TAtlasIdeSearchPainter.Create;
  end;
  if FHost = nil then
  begin
    FHost := TAtlasEditorBarHost.Create('Suchleiste', TAtlasFeature.Search,
      function(AEditorParent: TWinControl): TControl
      begin
        Result := CreateBar;
      end,
      procedure(ABar: TControl; AEditorParent: TWinControl)
      begin
        Place(TAtlasSearchBar(ABar), AEditorParent);
      end);
    FHost.OnRemoved :=
      procedure(ABar: TControl)
      begin
        Removed(ABar);
      end;
  end;
  CreateTimers;
  if TAtlasIdeSearchSession.Histories = nil then
  begin
    TAtlasIdeSearchSession.Histories := TAtlasIdeSearchHistories.Create(TAtlasIdeSettings.Current.SearchHistory);
  end;
  TAtlasIdeSearchSession.Histories.Load;
end;

class procedure TAtlasIdeSearch.CreateTimers;
begin
  if FProbeOwner = nil then
  begin
    FProbeOwner := TProbeOwner.Create(nil);
  end;
  if FProbe = nil then
  begin
    FProbe := TTimer.Create(FProbeOwner);
    FProbe.Enabled := False;
    FProbe.Interval := cProbeMs;
    FProbe.OnTimer := FProbeOwner.Tick;
  end;
  if TAtlasIdeSearchSession.Files.Timer = nil then
  begin
    TAtlasIdeSearchSession.Files.Timer := TTimer.Create(FProbeOwner);
    TAtlasIdeSearchSession.Files.Timer.Enabled := False;
    TAtlasIdeSearchSession.Files.Timer.Interval := cFilesDelayMs;
    TAtlasIdeSearchSession.Files.Timer.OnTimer := FProbeOwner.FilesTick;
  end;
end;

class procedure TAtlasIdeSearch.Uninstall;
begin
  FreeAndNil(FPainter);
  // Erst die Suche über Dateien beenden (wartet auf den Thread), dann das Fenster und die Leisten.
  TAtlasIdeSearchAcrossFiles.Drop;
  TAtlasIdeSearchReplaceWindow.Release;
  FreeAndNil(FHost);
  // Die Takte gehören ihrem Besitzer.
  FProbe := nil;
  TAtlasIdeSearchSession.Files.Timer := nil;
  FEntered := nil;
  FreeAndNil(FProbeOwner);
  TAtlasIdeSearchSession.Bar := nil;
  TAtlasIdeSearchSession.OnMessage := nil;
  TAtlasIdeSearchSession.Highlight := False;
  TAtlasIdeSearchSession.ListedKey := '';
  TAtlasIdeSearchSession.Last := Default(TAtlasSearchQuery);
  TAtlasIdeSearchSession.SaveHistories;
  FreeAndNil(TAtlasIdeSearchSession.Histories);
end;

class procedure TAtlasIdeSearch.ApplySettings;
var
  mListed: Boolean;
begin
  mListed := TAtlasIdeSettings.Current.SearchResultsInMessages;
  if not mListed then
  begin
    TAtlasIdeSearchMessages.Clear;
    TAtlasIdeSearchSession.ListedKey := '';
  end;
  // Verlauf kürzen; 0 = aus (#893).
  if TAtlasIdeSearchSession.Histories <> nil then
  begin
    TAtlasIdeSearchSession.Histories.SetCapacity(TAtlasIdeSettings.Current.SearchHistory);
  end;
  TAtlasIdeSearchSession.SaveHistories;
  // Ohne Bereiche über Dateien bzw. ohne Ersetzen: laufende Suche und Fenster weg.
  if not TAtlasIdeSettings.Current.SearchMultiFile or not TAtlasIdeSettings.Current.SearchReplace then
  begin
    TAtlasIdeSearchReplaceWindow.Hide;
  end;
  if not TAtlasIdeSettings.Current.SearchMultiFile then
  begin
    TAtlasIdeSearchAcrossFiles.Drop;
  end;
  if FHost <> nil then
  begin
    FHost.ForEach(
      procedure(ABar: TControl)
      begin
        TAtlasSearchBar(ABar).ListVisible := mListed;
        TAtlasSearchBar(ABar).Features := Features;
      end);
  end;
end;

class procedure TAtlasIdeSearch.ThemeChanged;
begin
  if FHost <> nil then
  begin
    FHost.ForEach(
      procedure(ABar: TControl)
      begin
        ThemeBar(TAtlasSearchBar(ABar));
      end);
  end;
  TAtlasIdeSearchReplaceWindow.ApplyTheme;
end;

class function TAtlasIdeSearch.Features: TAtlasSearchBarFeatures;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := TAtlasSearchBarFeatures.Create(mSettings.SearchReplace, mSettings.SearchRegex, mSettings.SearchMultiFile);
end;

class procedure TAtlasIdeSearch.ThemeBar(ABar: TAtlasSearchBar);
begin
  TAtlasIdeDockWindow.ApplyIdeTheme(ABar);
end;

class function TAtlasIdeSearch.BarFor(const AWindow: INTAEditWindow): TAtlasSearchBar;
begin
  Result := nil;
  if FHost <> nil then
  begin
    Result := TAtlasSearchBar(FHost.EnsureFor(AWindow));
  end;
end;

/// <summary>Eigene Methode: Jede Leiste braucht ihre eigene gefangene Variable.</summary>
class function TAtlasIdeSearch.CreateBar: TAtlasSearchBar;
var
  mBar: TAtlasSearchBar;
begin
  mBar := TAtlasSearchBar.Create(nil);
  Result := mBar;
  mBar.Visible := False;
  mBar.OnQueryChanged := Guarded(mBar,
    procedure
    begin
      TAtlasIdeSearchSteps.Sync(True);
    end);
  mBar.OnStep := GuardedStep(mBar,
    procedure(ABackward: Boolean)
    begin
      BarStep(ABackward);
    end);
  mBar.OnList := Guarded(mBar,
    procedure
    begin
      TAtlasIdeSearchSteps.List;
    end);
  mBar.OnClose := Guarded(mBar, CloseBar);
  mBar.OnReplace := Guarded(mBar,
    procedure
    begin
      TAtlasIdeSearchReplacing.Replace;
    end);
  mBar.OnReplaceAll := Guarded(mBar,
    procedure
    begin
      TAtlasIdeSearchReplacing.ReplaceAll;
    end);
  mBar.OnChoose := Guarded(mBar,
    procedure
    begin
      TAtlasIdeSearchReplacing.Choose;
    end);
  mBar.OnCancel := Guarded(mBar,
    procedure
    begin
      TAtlasIdeSearchReplacing.Cancel;
    end);
  mBar.OnReplaceShown := Guarded(mBar,
    procedure
    begin
      TAtlasIdeSearchCounter.Preview;
    end);
  mBar.OnControlEnter :=
    procedure(AControl: TWinControl)
    begin
      if mBar = TAtlasIdeSearchSession.Bar then
      begin
        FEntered := AControl;
        FEnteredAt := TThread.GetTickCount64;
      end;
    end;
  // Verlauf und Teile nach den Einstellungen (#893); Platz und Farben setzt Place über den Host (#1248).
  mBar.SetHistories(TAtlasIdeSearchSession.Histories.Search, TAtlasIdeSearchSession.Histories.Replace);
  mBar.Features := Features;
end;

class procedure TAtlasIdeSearch.Place(ABar: TAtlasSearchBar; AParent: TWinControl);
begin
  if ABar.Parent = AParent then
  begin
    Exit;
  end;
  // Unter dem Editor: zuerst ganz unten einhängen, dann unten ausrichten.
  ABar.Top := AParent.ClientHeight;
  ABar.Align := alBottom;
  ABar.Parent := AParent;
  ThemeBar(ABar);
end;

class procedure TAtlasIdeSearch.Removed(ABar: TControl);
begin
  if TAtlasIdeSearchSession.Bar = ABar then
  begin
    TAtlasIdeSearchSession.Bar := nil;
    StopProbe;
  end;
end;

class procedure TAtlasIdeSearch.Open(AInMethod, AReplace: Boolean);
var
  mView: IOTAEditView;
  mEditors: INTAEditorServices;
  mBar: TAtlasSearchBar;
  mText: string;
  mLines: TArray<string>;
  mCursor: TAtlasSearchPos;
  mSelection: TAtlasSearchArea;
  mHasSelection: Boolean;
  mQuery: TAtlasSearchQuery;
begin
  mBar := nil;
  if TAtlasIdeSearchEditor.TopView(mView) and Supports(BorlandIDEServices, INTAEditorServices, mEditors) then
  begin
    mBar := BarFor(mEditors.TopEditWindow);
  end;
  if mBar = nil then
  begin
    Exit;
  end;
  mText := TAtlasEditorBuffer.Text(mView.Buffer);
  mLines := TTextLines.SplitLines(mText);
  mCursor := TAtlasIdeSearchEditor.CursorOf(mView, mLines);
  mHasSelection := TAtlasIdeSearchEditor.SelectionOf(mView, mLines, mSelection);
  // Bereich Unit; Methode nur mit „In Methode suchen“, mehrzeilige Markierung als Auswahl.
  mQuery := TAtlasSearchResults.StartQuery(TAtlasIdeSearchSession.Last,
    Proposal(mLines, mCursor, mSelection, mHasSelection),
    mHasSelection and (mSelection.Start.Line <> mSelection.Stop.Line), AInMethod);
  // Ursprung der Suche: Anfang einer Markierung, sonst der Cursor.
  TAtlasIdeSearchSession.Origin := mCursor;
  if mHasSelection then
  begin
    TAtlasIdeSearchSession.Origin := mSelection.Start;
  end;
  TAtlasIdeSearchSession.Selection := mSelection;
  TAtlasIdeSearchSession.FileName := mView.Buffer.FileName;
  // Eine andere Leiste (anderes Editorfenster) beenden.
  if (TAtlasIdeSearchSession.Bar <> nil) and (TAtlasIdeSearchSession.Bar <> mBar) then
  begin
    TAtlasIdeSearchSession.Bar.Visible := False;
  end;
  TAtlasIdeSearchSession.Bar := mBar;
  mBar.ListVisible := TAtlasIdeSettings.Current.SearchResultsInMessages;
  mBar.Features := Features;
  // Strg+H mit, Strg+F ohne Ersetzen-Zeile.
  mBar.ReplaceShown := AReplace;
  mBar.Prepare(mQuery, Levels(mText, mCursor), mHasSelection);
  mBar.Visible := True;
  // Vor alle Geschwister: Kein Fenster der IDE soll über der Leiste liegen.
  mBar.BringToFront;
  LogLayout(mBar);
  mBar.FocusText;
  FProbed := 0;
  FEntered := nil;
  if FProbe <> nil then
  begin
    FProbe.Enabled := True;
  end;
  // Hervorheben und zählen, ohne zu springen: Der Vorschlag steht meist schon am Cursor.
  TAtlasIdeSearchSteps.Sync(False);
end;

class procedure TAtlasIdeSearch.BarStep(ABackward: Boolean);
begin
  TAtlasIdeSearchSession.SaveHistories;
  TAtlasIdeSearchSteps.Sync(False);
  TryNext(ABackward);
end;

class procedure TAtlasIdeSearch.CloseBar;
var
  mBar: TAtlasSearchBar;
begin
  mBar := TAtlasIdeSearchSession.Bar;
  if mBar = nil then
  begin
    Exit;
  end;
  StopProbe;
  TAtlasIdeSearchSession.SaveHistories;
  if TAtlasIdeSearchSession.Files.Timer <> nil then
  begin
    TAtlasIdeSearchSession.Files.Timer.Enabled := False;
  end;
  // Eine laufende Suche über Dateien endet mit der Leiste; fertige Ergebnisse bleiben für F3.
  if TAtlasIdeFileSearch.Running then
  begin
    TAtlasIdeSearchAcrossFiles.Drop;
  end;
  mBar.Visible := False;
  TAtlasIdeSearchSession.Highlight := False;
  TAtlasIdeSearchSession.Repaint;
  TAtlasEditorBarHost.FocusEditor(mBar);
end;

class procedure TAtlasIdeSearch.StopProbe;
begin
  if FProbe <> nil then
  begin
    FProbe.Enabled := False;
  end;
  FEntered := nil;
  FProbed := 0;
end;

/// <summary>Einmal je Leiste: Lage von Editor und Leiste im gemeinsamen Eltern-Steuerelement (Diagnose).</summary>
class procedure TAtlasIdeSearch.LogLayout(ABar: TAtlasSearchBar);
var
  mParent: TWinControl;
  mIndex: Integer;
  mChild: TControl;
  mParts: string;
begin
  if ABar.Tag <> 0 then
  begin
    Exit;
  end;
  ABar.Tag := 1;
  mParent := ABar.Parent;
  if mParent = nil then
  begin
    Exit;
  end;
  mParts := '';
  for mIndex := 0 to mParent.ControlCount - 1 do
  begin
    mChild := mParent.Controls[mIndex];
    mParts := mParts + Format(' [%s %s Align %d, %d,%d %dx%d, sichtbar %s]', [mChild.ClassName, mChild.Name,
      Ord(mChild.Align), mChild.Left, mChild.Top, mChild.Width, mChild.Height, BoolToStr(mChild.Visible, True)]);
  end;
  TAtlasGuard.Log(Format('Suchleiste: in %s %s (%dx%d):%s', [mParent.ClassName, mParent.Name, mParent.ClientWidth,
    mParent.ClientHeight, mParts]));
end;

class procedure TAtlasIdeSearch.EnableBars;
begin
  // Beim Schließen aller Editoren (Projektwechsel) sperrt die IDE jedes Steuerelement im Editor-Panel und gibt danach
  // nur ihre eigenen wieder frei; die Suchleiste flackerte dann beim Klick nur kurz und blieb taub.
  if FHost <> nil then
  begin
    FHost.Enable;
  end;
end;

class procedure TAtlasIdeSearch.RestoreFocus(ABar: TAtlasSearchBar);
begin
  if (FEntered = nil) or ABar.HasFocus then
  begin
    Exit;
  end;
  if TThread.GetTickCount64 - FEnteredAt <= cFocusGraceMs then
  begin
    TAtlasGuard.Log(Format('Suchleiste: Fokus nach dem Klick an %s %s verloren (an %s); hole ihn zurück',
      [FEntered.ClassName, FEntered.Name, WindowName(Winapi.Windows.GetFocus)]));
    if FEntered.CanFocus then
    begin
      FEntered.SetFocus;
    end;
  end;
  FEntered := nil;
end;

class procedure TAtlasIdeSearch.Probe;
var
  mBar: TAtlasSearchBar;
  mCursor: TPoint;
  mWindow: HWND;
begin
  EnableBars;
  mBar := TAtlasIdeSearchSession.Bar;
  if (mBar = nil) or not mBar.HandleAllocated or not mBar.Showing then
  begin
    Exit;
  end;
  RestoreFocus(mBar);
  // Liegt über der Leiste ein anderes Fenster, bekommt sie keine Klicks: protokollieren, nach vorn holen.
  if not GetCursorPos(mCursor) or not PtInRect(mBar.ClientRect, mBar.ScreenToClient(mCursor)) then
  begin
    Exit;
  end;
  mWindow := WindowFromPoint(mCursor);
  if (mWindow = FProbed) or (mWindow = mBar.Handle) or IsChild(mBar.Handle, mWindow) then
  begin
    FProbed := mWindow;
    Exit;
  end;
  FProbed := mWindow;
  TAtlasGuard.Log(Format('Suchleiste: Über der Leiste liegt ein anderes Fenster (%s); hole die Leiste nach vorn',
    [WindowName(mWindow)]));
  mBar.BringToFront;
end;

class procedure TAtlasIdeSearch.Show;
begin
  EnableBars;
  Open(False, False);
end;

class procedure TAtlasIdeSearch.ShowInMethod;
begin
  EnableBars;
  Open(True, False);
end;

class procedure TAtlasIdeSearch.ShowReplace;
begin
  EnableBars;
  Open(False, TAtlasIdeSettings.Current.SearchReplace);
end;

class function TAtlasIdeSearch.TryNext(ABackward: Boolean): Boolean;
begin
  Result := TAtlasIdeSearchSteps.TryNext(ABackward);
end;

class procedure TAtlasIdeSearch.FindNext;
begin
  if not TryNext(False) then
  begin
    Show;
  end;
end;

class procedure TAtlasIdeSearch.FindPrevious;
begin
  if not TryNext(True) then
  begin
    Show;
  end;
end;

class procedure TAtlasIdeSearch.ClearHighlights;
begin
  if TAtlasIdeSearchSession.BarOpen then
  begin
    CloseBar;
  end
  else
  begin
    TAtlasIdeSearchSession.Highlight := False;
    TAtlasIdeSearchSession.Repaint;
  end;
end;

end.
