unit Atlas.IDE.Foundation.GutterColumns;

// Eigene Spalten der Zeilenleiste (RequestGutterColumn) abgeben, bevor die
// IDE ein Editorfenster abbaut (#1233): Stand beim Abbau eines Editorfensters
// noch eine angeforderte Spalte, gab die IDE beim Beenden eine Komponente
// eines anderen Experten im Editorfenster erst nach dem Entladen von dessen
// DLL frei (Zugriffsverletzung in rtl370, Offset 133BE4). Atlas entlud erst
// danach; Entfernen beim Entladen half nicht mehr. Wurde Atlas entladen,
// solange die Editorfenster offen waren, endete die IDE sauber.
// - Ein Beobachter der Editorfenster (INTAEditServicesNotifier) ruft beim
//   Abbau eines Fensters (WindowNotification mit opRemove) die Abgabe aller
//   angemeldeten Spalten auf.
// - Danach ist das Anfordern für PauseMs gesperrt (Allowed): Beim Beenden
//   baut die IDE die Fenster nacheinander ab; ein Zeitgeber, der dazwischen
//   wieder anfordert, legte die Spalte erneut an. Läuft die IDE weiter (ein
//   weiteres Editorfenster geschlossen), holen die Dienste ihre Spalte danach
//   wieder.
// Nur im Hauptthread.

interface

uses
  System.SysUtils;

type
  TAtlasIdeGutterColumns = class
  public const
    /// <summary>So lange nach dem Abbau eines Editorfensters keine Spalte anfordern.</summary>
    PauseMs = 2000;
  public
    /// <summary>ADrop gibt die Spalte des Dienstes ab; Ergebnis für Unregister.</summary>
    class function Register(const ADrop: TProc): Integer; static;
    class procedure Unregister(AHandle: Integer); static;
    /// <summary>Darf ein Dienst jetzt eine Spalte anfordern?</summary>
    class function Allowed: Boolean; static;
  end;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  ToolsAPI,
  DockForm,
  Atlas.Core.Diagnostics.Guard;

type
  TWindowWatch = class(TNotifierObject, INTAEditServicesNotifier)
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

var
  Drops: TDictionary<Integer, TProc>;
  NextHandle: Integer;
  WatchIndex: Integer = -1;
  PausedUntil: UInt64;

procedure DropAll;
var
  Drop: TProc;
begin
  if Drops = nil then
    Exit;
  PausedUntil := TThread.GetTickCount64 + TAtlasIdeGutterColumns.PauseMs;
  for Drop in Drops.Values do
    try
      Drop();
    except
      on E: Exception do
        TAtlasGuard.Log('Spalten der Zeilenleiste: Abgabe fehlgeschlagen: ' + E.ClassName);
    end;
end;

{ TWindowWatch }

procedure TWindowWatch.WindowShow(const EditWindow: INTAEditWindow; Show, LoadedFromDesktop: Boolean);
begin
end;

procedure TWindowWatch.WindowNotification(const EditWindow: INTAEditWindow; Operation: TOperation);
begin
  if Operation = opRemove then
    DropAll;
end;

procedure TWindowWatch.WindowActivated(const EditWindow: INTAEditWindow);
begin
end;

procedure TWindowWatch.WindowCommand(const EditWindow: INTAEditWindow; Command, Param: Integer; var Handled: Boolean);
begin
end;

procedure TWindowWatch.EditorViewActivated(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
begin
end;

procedure TWindowWatch.EditorViewModified(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
begin
end;

procedure TWindowWatch.DockFormVisibleChanged(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

procedure TWindowWatch.DockFormUpdated(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

procedure TWindowWatch.DockFormRefresh(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

{ TAtlasIdeGutterColumns }

class function TAtlasIdeGutterColumns.Register(const ADrop: TProc): Integer;
var
  Editors: IOTAEditorServices;
begin
  if Drops = nil then
    Drops := TDictionary<Integer, TProc>.Create;
  if (WatchIndex < 0) and Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
    WatchIndex := Editors.AddNotifier(TWindowWatch.Create);
  Inc(NextHandle);
  Result := NextHandle;
  Drops.Add(Result, ADrop);
end;

class procedure TAtlasIdeGutterColumns.Unregister(AHandle: Integer);
var
  Editors: IOTAEditorServices;
begin
  if Drops = nil then
    Exit;
  Drops.Remove(AHandle);
  if Drops.Count > 0 then
    Exit;
  if (WatchIndex >= 0) and Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
    Editors.RemoveNotifier(WatchIndex);
  WatchIndex := -1;
  FreeAndNil(Drops);
end;

class function TAtlasIdeGutterColumns.Allowed: Boolean;
begin
  Result := TThread.GetTickCount64 >= PausedUntil;
end;

end.
