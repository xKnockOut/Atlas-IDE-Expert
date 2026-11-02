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
  Atlas.UI.Strings,
  Atlas.UI.Commands.Palette,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings;

const
  TickMs = 150;

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
    Exit;
  Result := TAtlasNavPlace.Create(AView.Buffer.FileName, AView.CursorPos.Line, AView.CursorPos.Col);
  Result.Time := Now;
end;

function WithExcerpt(const AView: IOTAEditView; const APlace: TAtlasNavPlace): TAtlasNavPlace;
begin
  Result := APlace;
  if (AView <> nil) and (APlace.Line > 0) then
    Result.Excerpt := TAtlasNavHistory.Excerpt(TAtlasEditorBuffer.LineText(AView, APlace.Line));
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
  Owner: TNavState;
  View: IOTAEditView;
begin
  Owner := FOwner;
  if (Owner = nil) or (EditView = nil) or not Enabled then
    Exit;
  View := EditView;
  // Keine Exception an die IDE (#493).
  TAtlasGuard.Run(TAtlasFeature.NavHistory,
    procedure
    begin
      Owner.Edited(View);
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
  Timer.Interval := TickMs;
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
  Key: string;
  Count, Known, Anchor: Integer;
begin
  Key := AnsiUpperCase(AView.Buffer.FileName);
  Count := AView.Buffer.GetLinesInBuffer;
  if LineCounts.TryGetValue(Key, Known) and (Known <> Count) then
  begin
    // Eingefügt bzw. gelöscht wurde an der Cursorstelle vor oder nach der Änderung.
    Anchor := ACursorLine;
    if SameText(Last.FileName, AView.Buffer.FileName) and (Last.Line > 0) then
      Anchor := Min(Anchor, Last.Line);
    History.LinesChanged(AView.Buffer.FileName, Anchor, Count - Known);
  end;
  LineCounts.AddOrSetValue(Key, Count);
end;

procedure TNavState.Edited(const AView: IOTAEditView);
var
  Place: TAtlasNavPlace;
begin
  Place := PlaceOf(AView);
  if Place.FileName = '' then
    Exit;
  TrackLines(AView, Place.Line);
  Place := WithExcerpt(AView, Place);
  History.Edited(Place);
  Modified := True;
  Last := Place;
end;

procedure TNavState.Tick(Sender: TObject);
var
  View: IOTAEditView;
  Current: TAtlasNavPlace;
begin
  try
    if not Enabled then
    begin
      Last := Default(TAtlasNavPlace);
      Exit;
    end;
    View := TAtlasEditorBuffer.ActiveView;
    if View = nil then
      Exit;
    Current := PlaceOf(View);
    if Current.FileName = '' then
      Exit;
    if Modified then
      Modified := False
    else if TAtlasNavHistory.IsJump(Last, Current) then
      History.Jumped(Last, Current)
    else if SameText(Last.FileName, Current.FileName) and (Last.Line = Current.Line) then
      // Unverändert: den Auszug nicht neu lesen.
      Exit;
    Last := WithExcerpt(View, Current);
    TrackLines(View, Current.Line);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.NavHistory, E);
  end;
end;

{ Befehle }

function Current(out APlace: TAtlasNavPlace): Boolean;
var
  View: IOTAEditView;
begin
  View := TAtlasEditorBuffer.ActiveView;
  APlace := WithExcerpt(View, PlaceOf(View));
  Result := APlace.FileName <> '';
end;

procedure GoTo_(const ATarget: TAtlasNavPlace);
var
  View: IOTAEditView;
begin
  TAtlasIdeNavigation.GoToLocation(ATarget.FileName, Max(0, ATarget.Line - 1), Max(0, ATarget.Column - 1));
  // Der eigene Sprung ist kein neuer Eintrag: Ausgangspunkt für den nächsten Tick ist das Ziel.
  if State <> nil then
  begin
    View := TAtlasEditorBuffer.ActiveView;
    State.Last := WithExcerpt(View, PlaceOf(View));
    State.Modified := False;
  end;
end;

{ TAtlasIdeNavHistory }

class function TAtlasIdeNavHistory.History: TAtlasNavHistory;
begin
  Result := nil;
  if State <> nil then
    Result := State.History;
end;

class procedure TAtlasIdeNavHistory.Install;
var
  Owner: TNavState;
  Editors: IOTAEditorServices;
begin
  Owner := TNavState.Create(nil);
  FState := Owner;
  if Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
  begin
    Owner.Notifier := TEditNotifier.Create;
    Owner.Notifier.FOwner := Owner;
    Owner.NotifierIndex := Editors.AddNotifier(Owner.Notifier);
  end;
end;

class procedure TAtlasIdeNavHistory.Uninstall;
var
  Owner: TNavState;
  Editors: IOTAEditorServices;
begin
  Owner := State;
  FState := nil;
  if Owner = nil then
    Exit;
  if Owner.Notifier <> nil then
    Owner.Notifier.FOwner := nil;
  // RemoveNotifier gibt die Referenz der IDE frei und damit den Beobachter (#493).
  if (Owner.NotifierIndex >= 0) and Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
    Editors.RemoveNotifier(Owner.NotifierIndex);
  Owner.Free;
end;

class procedure TAtlasIdeNavHistory.GoBack;
var
  Here, Target: TAtlasNavPlace;
begin
  if (State = nil) or not Enabled then
    Exit;
  Current(Here);
  if State.History.StepBack(Here, Target) then
    GoTo_(Target);
end;

class procedure TAtlasIdeNavHistory.GoForward;
var
  Here, Target: TAtlasNavPlace;
begin
  if (State = nil) or not Enabled then
    Exit;
  Current(Here);
  if State.History.StepForward(Here, Target) then
    GoTo_(Target);
end;

class procedure TAtlasIdeNavHistory.GoLastEdit;
var
  Here, Target: TAtlasNavPlace;
begin
  if (State = nil) or not Enabled then
    Exit;
  Current(Here);
  if State.History.LastEdit(Here, Target) then
  begin
    // Wie ein Sprung: die Ausgangsstelle kommt auf den Zurück-Stapel.
    State.History.Jumped(Here, Target);
    GoTo_(Target);
  end;
end;

function KindText(AKind: TAtlasNavKind): string;
begin
  case AKind of
    TAtlasNavKind.Back:
      Result := TAtlasStrings.Text(TAtlasTextId.NavKindBack);
    TAtlasNavKind.Ahead:
      Result := TAtlasStrings.Text(TAtlasTextId.NavKindAhead);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.NavKindEdit);
  end;
end;

class procedure TAtlasIdeNavHistory.ShowList;
var
  Entries: TArray<TAtlasNavListEntry>;
  Commands: TArray<TAtlasCommand>;
  Command: TAtlasCommand;
  Index: Integer;
  Window: TAtlasPaletteWindow;
  Area: TRect;
begin
  if (State = nil) or not Enabled then
    Exit;
  Entries := State.History.Entries;
  Commands := nil;
  for Index := 0 to High(Entries) do
  begin
    Command := Default(TAtlasCommand);
    Command.Id := IntToStr(Index);
    Command.Caption := ExtractFileName(Entries[Index].Place.FileName) + ':' + IntToStr(Entries[Index].Place.Line);
    Command.Path := Entries[Index].Place.Excerpt;
    Command.ShortCut := KindText(Entries[Index].Kind) + ' · ' + FormatDateTime('hh":"nn', Entries[Index].Place.Time);
    Commands := Commands + [Command];
  end;
  if Length(Commands) = 0 then
  begin
    Command := Default(TAtlasCommand);
    Command.Caption := TAtlasStrings.Text(TAtlasTextId.NavEmpty);
    Commands := [Command];
  end;
  Window := TAtlasPaletteWindow.CreatePalette(Application, Commands, nil, TAtlasIdeStyle.Colors);
  Window.Prompt := TAtlasStrings.Text(TAtlasTextId.NavListPrompt);
  Window.KeepOrder := True;
  Window.OnExecute :=
    procedure(ACommand: TAtlasCommand)
    var
      Chosen: Integer;
      Here, Target: TAtlasNavPlace;
    begin
      Chosen := StrToIntDef(ACommand.Id, -1);
      if (State = nil) or (Chosen < 0) or (Chosen > High(Entries)) then
        Exit;
      Current(Here);
      if State.History.Jump(Entries[Chosen], Here, Target) then
        GoTo_(Target);
    end;
  if Screen.ActiveForm <> nil then
    Area := Screen.ActiveForm.BoundsRect
  else if Application.MainForm <> nil then
    Area := Application.MainForm.BoundsRect
  else
    Area := Screen.WorkAreaRect;
  Window.ShowOver(Area);
end;

end.
