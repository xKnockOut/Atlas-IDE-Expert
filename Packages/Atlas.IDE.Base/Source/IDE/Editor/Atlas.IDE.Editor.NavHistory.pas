unit Atlas.IDE.Editor.NavHistory;

// Navigationsverlauf über Dateien hinweg (#504) in der IDE:
// - Sprünge: Ein Zeitgeber (150 ms) liest Datei und Cursor des aktuellen
//   Editors. Wechselt die Datei oder springt der Cursor um mehr als 10 Zeilen,
//   ohne dass dazwischen getippt wurde, merkt TAtlasNavHistory die
//   Ausgangsstelle. So zählen alle Wege: Gehe zu Definition der IDE und von
//   Atlas, Referenzen, Befehlspalette, Strg+P, Suchergebnisse, Meldungsansicht.
// - Bearbeitungsstellen: EditorViewModified merkt die Cursorzeile. Ändert sich
//   die Zeilenzahl des Puffers, verschieben sich die Einträge der Datei unter
//   der kleineren von alter und neuer Cursorzeile.
// - Abgrenzung zur IDE: Deren Zurück/Vor (Alt+Links/Rechts) kennt nur ihre
//   eigene Strg+Klick-Navigation. Atlas führt diese Sprünge mit und belegt die
//   Tasten darum mit Vorrang (Seite „Tastenkonflikte“); mit navHistory.enabled
//   aus behält die IDE sie. Keine Taste ist doppelt belegt.
// - Sprünge öffnen geschlossene Dateien wieder (TAtlasIdeNavigation).
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Core.Editor.NavHistory;

type
  TAtlasIdeNavHistory = class
  private class var
    FState: TObject;
  public
    class procedure Install; static;
    class procedure Uninstall; static;
    /// <summary>Zurück zur vorigen Stelle.</summary>
    class procedure GoBack; static;
    /// <summary>Vor zur nächsten Stelle.</summary>
    class procedure GoForward; static;
    /// <summary>Wie GoBack bzw. GoForward; True, wenn ein Sprung lief (Maustasten, #1889).</summary>
    class function Step(AForward: Boolean): Boolean; static;
    /// <summary>Letzte Bearbeitungsstelle; jeder weitere Aufruf eine davor.</summary>
    class procedure GoLastEdit; static;
    /// <summary>Verlauf als Liste wie die Befehlspalette.</summary>
    class procedure ShowList; static;
    /// <summary>Verlauf der Sitzung (für Tests und Diagnose); nil vor Install.</summary>
    class function History: TAtlasNavHistory; static;
  end;

implementation

uses
  System.Types,
  System.Math,
  System.Generics.Collections,
  Vcl.ExtCtrls,
  Vcl.Forms,
  ToolsAPI,
  DockForm,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Commands.Palette,
  Atlas.UI.Editor.Strings,
  Atlas.UI.Commands.Palette,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings;

const
  cTickMs = 150;

type
  TNavState = class;

  TEditNotifier = class(TNotifierObject, INTAEditServicesNotifier)
  private
    FOwner: TNavState;
  public
    procedure WindowShow(const EditWindow: INTAEditWindow; Show, LoadedFromDesktop: Boolean);
    procedure WindowNotification(const EditWindow: INTAEditWindow; Operation: TOperation);
    procedure WindowActivated(const EditWindow: INTAEditWindow);
    procedure WindowCommand(const EditWindow: INTAEditWindow; Command, Param: Integer; var Handled: Boolean);
    procedure EditorViewActivated(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
    procedure EditorViewModified(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
    procedure DockFormVisibleChanged(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
    procedure DockFormUpdated(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
    procedure DockFormRefresh(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
  end;

  TNavState = class(TComponent)
  private
    procedure Tick(Sender: TObject);
  public
    History: TAtlasNavHistory;
    Timer: TTimer;
    Notifier: TEditNotifier;
    NotifierIndex: Integer;
    /// <summary>Letzte gelesene Stelle; FileName = '' ohne.</summary>
    Last: TAtlasNavPlace;
    /// <summary>Seit dem letzten Tick wurde getippt: kein Sprung.</summary>
    Modified: Boolean;
    /// <summary>Großgeschriebener Dateiname → Zeilenzahl des Puffers.</summary>
    LineCounts: TDictionary<string, Integer>;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Edited(const AView: IOTAEditView);
    procedure TrackLines(const AView: IOTAEditView; ACursorLine: Integer);
  end;

function State: TNavState;
begin
  Result := TNavState(TAtlasIdeNavHistory.FState);
end;

function PlaceOf(const AView: IOTAEditView): TAtlasNavPlace;
begin
  Result := Default(TAtlasNavPlace);
  if (AView = nil) or (AView.Buffer = nil) then
  begin
    Exit;
  end;
  Result := TAtlasNavPlace.Create(AView.Buffer.FileName, AView.CursorPos.Line, AView.CursorPos.Col);
  Result.Time := Now;
end;

function WithExcerpt(const AView: IOTAEditView; const APlace: TAtlasNavPlace): TAtlasNavPlace;
begin
  Result := APlace;
  if (AView <> nil) and (APlace.Line > 0) then
  begin
    Result.Excerpt := TAtlasNavHistory.Excerpt(TAtlasEditorBuffer.LineText(AView, APlace.Line));
  end;
end;

function Enabled: Boolean;
begin
  Result := TAtlasIdeSettings.Current.NavHistory;
end;

{ TEditNotifier }

procedure TEditNotifier.WindowShow(const EditWindow: INTAEditWindow; Show, LoadedFromDesktop: Boolean);
begin
end;

procedure TEditNotifier.WindowNotification(const EditWindow: INTAEditWindow; Operation: TOperation);
begin
end;

procedure TEditNotifier.WindowActivated(const EditWindow: INTAEditWindow);
begin
end;

procedure TEditNotifier.WindowCommand(const EditWindow: INTAEditWindow; Command, Param: Integer;
  var Handled: Boolean);
begin
end;

procedure TEditNotifier.EditorViewActivated(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
begin
end;

procedure TEditNotifier.EditorViewModified(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
var
  mOwner: TNavState;
  mView: IOTAEditView;
begin
  mOwner := FOwner;
  if (mOwner = nil) or (EditView = nil) or not Enabled then
  begin
    Exit;
  end;
  mView := EditView;
  // Keine Exception an die IDE (#493).
  TAtlasGuard.Run(TAtlasFeature.NavHistory,
    procedure
    begin
      mOwner.Edited(mView);
    end);
end;

procedure TEditNotifier.DockFormVisibleChanged(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

procedure TEditNotifier.DockFormUpdated(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

procedure TEditNotifier.DockFormRefresh(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

{ TNavState }

constructor TNavState.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  NotifierIndex := -1;
  History := TAtlasNavHistory.Create;
  LineCounts := TDictionary<string, Integer>.Create;
  Timer := TTimer.Create(Self);
  Timer.Interval := cTickMs;
  Timer.OnTimer := Tick;
  Timer.Enabled := True;
end;

destructor TNavState.Destroy;
begin
  Timer.Enabled := False;
  LineCounts.Free;
  History.Free;
  inherited;
end;

procedure TNavState.TrackLines(const AView: IOTAEditView; ACursorLine: Integer);
var
  mKey: string;
  mCount, mKnown, mAnchor: Integer;
begin
  mKey := AnsiUpperCase(AView.Buffer.FileName);
  mCount := AView.Buffer.GetLinesInBuffer;
  if LineCounts.TryGetValue(mKey, mKnown) and (mKnown <> mCount) then
  begin
    // Eingefügt bzw. gelöscht wurde an der Cursorstelle vor oder nach der Änderung.
    mAnchor := ACursorLine;
    if SameText(Last.FileName, AView.Buffer.FileName) and (Last.Line > 0) then
    begin
      mAnchor := Min(mAnchor, Last.Line);
    end;
    History.LinesChanged(AView.Buffer.FileName, mAnchor, mCount - mKnown);
  end;
  LineCounts.AddOrSetValue(mKey, mCount);
end;

procedure TNavState.Edited(const AView: IOTAEditView);
var
  mPlace: TAtlasNavPlace;
begin
  mPlace := PlaceOf(AView);
  if mPlace.FileName = '' then
  begin
    Exit;
  end;
  TrackLines(AView, mPlace.Line);
  mPlace := WithExcerpt(AView, mPlace);
  History.Edited(mPlace);
  Modified := True;
  Last := mPlace;
end;

procedure TNavState.Tick(Sender: TObject);
var
  mView: IOTAEditView;
  mCurrent: TAtlasNavPlace;
begin
  try
    if not Enabled then
    begin
      Last := Default(TAtlasNavPlace);
      Exit;
    end;
    mView := TAtlasEditorBuffer.ActiveView;
    if mView = nil then
    begin
      Exit;
    end;
    mCurrent := PlaceOf(mView);
    if mCurrent.FileName = '' then
    begin
      Exit;
    end;
    if Modified then
    begin
      Modified := False;
    end
    else if TAtlasNavHistory.IsJump(Last, mCurrent) then
    begin
      History.Jumped(Last, mCurrent);
    end
    else if SameText(Last.FileName, mCurrent.FileName) and (Last.Line = mCurrent.Line) then
    begin
      // Unverändert: den Auszug nicht neu lesen.
      Exit;
    end;
    Last := WithExcerpt(mView, mCurrent);
    TrackLines(mView, mCurrent.Line);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.NavHistory, E);
  end;
end;

{ Befehle }

function Current(out APlace: TAtlasNavPlace): Boolean;
var
  mView: IOTAEditView;
begin
  mView := TAtlasEditorBuffer.ActiveView;
  APlace := WithExcerpt(mView, PlaceOf(mView));
  Result := APlace.FileName <> '';
end;

procedure GoTo_(const ATarget: TAtlasNavPlace);
var
  mView: IOTAEditView;
begin
  TAtlasIdeNavigation.GoToLocation(ATarget.FileName, Max(0, ATarget.Line - 1), Max(0, ATarget.Column - 1));
  // Der eigene Sprung ist kein neuer Eintrag: Ausgangspunkt für den nächsten Tick ist das Ziel.
  if State <> nil then
  begin
    mView := TAtlasEditorBuffer.ActiveView;
    State.Last := WithExcerpt(mView, PlaceOf(mView));
    State.Modified := False;
  end;
end;

{ TAtlasIdeNavHistory }

class function TAtlasIdeNavHistory.History: TAtlasNavHistory;
begin
  Result := nil;
  if State <> nil then
  begin
    Result := State.History;
  end;
end;

class procedure TAtlasIdeNavHistory.Install;
var
  mOwner: TNavState;
  mEditors: IOTAEditorServices;
begin
  mOwner := TNavState.Create(nil);
  FState := mOwner;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    mOwner.Notifier := TEditNotifier.Create;
    mOwner.Notifier.FOwner := mOwner;
    mOwner.NotifierIndex := mEditors.AddNotifier(mOwner.Notifier);
  end;
end;

class procedure TAtlasIdeNavHistory.Uninstall;
var
  mOwner: TNavState;
  mEditors: IOTAEditorServices;
begin
  mOwner := State;
  FState := nil;
  if mOwner = nil then
  begin
    Exit;
  end;
  if mOwner.Notifier <> nil then
  begin
    mOwner.Notifier.FOwner := nil;
  end;
  // RemoveNotifier gibt die Referenz der IDE frei und damit den Beobachter (#493).
  if (mOwner.NotifierIndex >= 0) and Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    mEditors.RemoveNotifier(mOwner.NotifierIndex);
  end;
  mOwner.Free;
end;

class procedure TAtlasIdeNavHistory.GoBack;
begin
  Step(False);
end;

class procedure TAtlasIdeNavHistory.GoForward;
begin
  Step(True);
end;

class function TAtlasIdeNavHistory.Step(AForward: Boolean): Boolean;
var
  mHere, mTarget: TAtlasNavPlace;
begin
  Result := False;
  if (State = nil) or not Enabled then
  begin
    Exit;
  end;
  Current(mHere);
  if AForward then
  begin
    Result := State.History.StepForward(mHere, mTarget);
  end
  else
  begin
    Result := State.History.StepBack(mHere, mTarget);
  end;
  if Result then
  begin
    GoTo_(mTarget);
  end;
end;

class procedure TAtlasIdeNavHistory.GoLastEdit;
var
  mHere, mTarget: TAtlasNavPlace;
begin
  if (State = nil) or not Enabled then
  begin
    Exit;
  end;
  Current(mHere);
  if State.History.LastEdit(mHere, mTarget) then
  begin
    // Wie ein Sprung: die Ausgangsstelle kommt auf den Zurück-Stapel.
    State.History.Jumped(mHere, mTarget);
    GoTo_(mTarget);
  end;
end;

function KindText(AKind: TAtlasNavKind): string;
begin
  case AKind of
    TAtlasNavKind.Back:
      Result := TAtlasEditorStrings.Text(TAtlasEditorTextId.NavKindBack);
    TAtlasNavKind.Ahead:
      Result := TAtlasEditorStrings.Text(TAtlasEditorTextId.NavKindAhead);
  else
    Result := TAtlasEditorStrings.Text(TAtlasEditorTextId.NavKindEdit);
  end;
end;

/// <summary>Je Eintrag eine Zeile der Palette; ohne Einträge eine Zeile „leer“.</summary>
function ListCommands(const AEntries: TArray<TAtlasNavListEntry>): TArray<TAtlasCommand>;
var
  mCommand: TAtlasCommand;
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(AEntries) do
  begin
    mCommand := Default(TAtlasCommand);
    mCommand.Id := IntToStr(mIndex);
    mCommand.Caption := ExtractFileName(AEntries[mIndex].Place.FileName) + ':' +
      IntToStr(AEntries[mIndex].Place.Line);
    mCommand.Path := AEntries[mIndex].Place.Excerpt;
    mCommand.ShortCut := KindText(AEntries[mIndex].Kind) + ' · ' +
      FormatDateTime('hh":"nn', AEntries[mIndex].Place.Time);
    Result := Result + [mCommand];
  end;
  if Length(Result) = 0 then
  begin
    mCommand := Default(TAtlasCommand);
    mCommand.Caption := TAtlasEditorStrings.Text(TAtlasEditorTextId.NavEmpty);
    Result := [mCommand];
  end;
end;

/// <summary>Fläche, über der die Palette erscheint: aktives Formular, Hauptfenster oder Arbeitsfläche.</summary>
function PaletteArea: TRect;
begin
  if Screen.ActiveForm <> nil then
  begin
    Result := Screen.ActiveForm.BoundsRect;
  end
  else if Application.MainForm <> nil then
  begin
    Result := Application.MainForm.BoundsRect;
  end
  else
  begin
    Result := Screen.WorkAreaRect;
  end;
end;

class procedure TAtlasIdeNavHistory.ShowList;
var
  mEntries: TArray<TAtlasNavListEntry>;
  mWindow: TAtlasPaletteWindow;
begin
  if (State = nil) or not Enabled then
  begin
    Exit;
  end;
  mEntries := State.History.Entries;
  mWindow := TAtlasPaletteWindow.CreatePalette(Application, ListCommands(mEntries), nil, TAtlasIdeStyle.Colors);
  mWindow.Prompt := TAtlasEditorStrings.Text(TAtlasEditorTextId.NavListPrompt);
  mWindow.KeepOrder := True;
  mWindow.OnExecute :=
    procedure(ACommand: TAtlasCommand)
    var
      mChosen: Integer;
      mHere, mTarget: TAtlasNavPlace;
    begin
      mChosen := StrToIntDef(ACommand.Id, -1);
      if (State = nil) or (mChosen < 0) or (mChosen > High(mEntries)) then
      begin
        Exit;
      end;
      Current(mHere);
      if State.History.Jump(mEntries[mChosen], mHere, mTarget) then
      begin
        GoTo_(mTarget);
      end;
    end;
  mWindow.ShowOver(PaletteArea);
end;

end.
