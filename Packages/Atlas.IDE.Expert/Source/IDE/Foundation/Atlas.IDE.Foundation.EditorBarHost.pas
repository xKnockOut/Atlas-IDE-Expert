unit Atlas.IDE.Foundation.EditorBarHost;

// Gemeinsamer Leisten-Host (#1248). Jede Leiste im Editor (Editorleiste,
// Statusleiste, Brotkrumen, Übersichtsleiste, Minimap, Suchleiste) braucht
// dieselbe Verwaltung; früher hatte jeder Dienst eine eigene Kopie, und jede
// Kopie hatte denselben Fehler mindestens einmal (zuletzt: Suchleiste nach
// dem Projektwechsel von der IDE gesperrt). Der Host übernimmt:
// - je Editorfenster eine Leiste: Ensure legt sie für jedes Fenster an
//   (Fenster, die später aufgehen, beim nächsten Takt) und ordnet sie über
//   den Haken Place ein; EnsureFor nur für ein Fenster (Suchleiste auf
//   Abruf). Schlüssel ist das Eltern-Steuerelement des Editors, nicht das
//   Elternteil der Leiste: Die Editorleiste kann in die Brotkrumenzeile
//   umziehen.
// - Wächter (FreeNotification): Gibt die IDE eine Leiste mit ihrem Fenster
//   frei, verschwindet sie aus der Liste; OnRemoved meldet das dem Dienst.
// - Freigabe nach der Sperre durch die IDE: Beim Schließen aller Editoren
//   (Projektwechsel) sperrt die IDE jedes Steuerelement im Editor-Panel und
//   gibt danach nur ihre eigenen frei. Enable gibt die Leiste (VCL) und ihre
//   Fenster (auch an der VCL vorbei mit EnableWindow gesperrte) wieder frei;
//   Ensure ruft es, sobald ein Editor aktiv ist.
// - Sperren protokollieren: Disabled schreibt den Aufrufer mit Stapel ins
//   Protokoll (höchstens MaxDisabledLogs je Host).
// - Thema: ForEach wendet Farben (oder anderes) auf jede Leiste an.
// - Absturzsicherung je Leiste: Anlegen, Einordnen und ForEach laufen je
//   Leiste in einem eigenen try; ein Fehler zählt für das Feature
//   (TAtlasGuard.Report), die übrigen Leisten laufen weiter. Guard blendet
//   die Leisten aus, solange die Sicherung des Features ausgelöst ist, und
//   danach wieder ein.
// - Abbau: Destroy (bzw. Clear) gibt alle Leisten frei; der Wächter schreibt
//   dabei nicht mehr zurück. Danach hält Atlas keine Leiste in einem
//   IDE-Fenster mehr (vgl. #1233).
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Vcl.Controls,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard;

type
  TAtlasEditorBarHost = class
  public type
    /// <summary>Neue Leiste für das Eltern-Steuerelement des Editors; noch ohne Parent.</summary>
    TCreateBar = reference to function(AEditorParent: TWinControl): TControl;
    /// <summary>Leiste einordnen (Parent, Align, Reihenfolge); beim Anlegen und bei jedem Ensure.</summary>
    TPlaceBar = reference to procedure(ABar: TControl; AEditorParent: TWinControl);
  public const
    /// <summary>So oft je Host den Aufrufer protokollieren, der eine Leiste sperrt.</summary>
    MaxDisabledLogs = 3;
  private type
    TWatcher = class(TComponent)
    private
      FHost: TAtlasEditorBarHost;
    protected
      procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    end;
  private
    FName: string;
    FFeature: TAtlasFeature;
    FCreate: TCreateBar;
    FPlace: TPlaceBar;
    FWatcher: TWatcher;
    FBars: TList<TControl>;
    /// <summary>Eltern-Steuerelement des Editors je Leiste (gleicher Index wie FBars).</summary>
    FParents: TList<TWinControl>;
    FHidden: Boolean;
    FDisabledLogged: Integer;
    FOnRemoved: TProc<TControl>;
    procedure Removed(ABar: TControl);
    function CreateFor(AEditorParent: TWinControl): TControl;
    procedure PlaceGuarded(ABar: TControl; AEditorParent: TWinControl);
    procedure Show(AShown: Boolean);
  public
    /// <summary>AName steht im Protokoll („Editorleiste“); AFeature ist die Sicherung der Leisten.</summary>
    constructor Create(const AName: string; AFeature: TAtlasFeature; const ACreate: TCreateBar;
      const APlace: TPlaceBar);
    destructor Destroy; override;
    /// <summary>Editor-Steuerelement eines Editorfensters; nil, wenn es (noch) keins hat.</summary>
    class function EditorOf(const AWindow: INTAEditWindow): TWinControl; static;
    /// <summary>Editor des vordersten Editorfensters; nil ohne.</summary>
    class function TopEditor: TWinControl; static;
    /// <summary>Fokus an den Editor des Fensters, in dem AControl liegt (Leiste schließen, Esc).</summary>
    class procedure FocusEditor(AControl: TControl); static;
    /// <summary>Für jedes Editorfenster die Leiste anlegen bzw. einordnen; danach gesperrte freigeben, wenn ein
    /// Editor aktiv ist.</summary>
    procedure Ensure;
    /// <summary>Leiste für ein Editorfenster anlegen bzw. einordnen; nil ohne Editor oder bei Fehler.</summary>
    function EnsureFor(const AWindow: INTAEditWindow): TControl;
    /// <summary>Leiste zum Eltern-Steuerelement des Editors; nil ohne.</summary>
    function BarOf(AEditorParent: TWinControl): TControl;
    /// <summary>Leiste des vordersten Editorfensters; nil ohne.</summary>
    function ActiveBar: TControl;
    /// <summary>Eltern-Steuerelement des Editors, zu dem ABar gehört; nil, wenn sie nicht von diesem Host ist.
    /// </summary>
    function EditorParentOf(ABar: TControl): TWinControl;
    function Contains(ABar: TControl): Boolean;
    function Bars: TArray<TControl>;
    function Count: Integer;
    /// <summary>AAction für jede Leiste, je Leiste abgesichert.</summary>
    procedure ForEach(const AAction: TProc<TControl>);
    /// <summary>Alle Leisten freigeben (Funktion aus, Einstellungen geändert, Abbau).</summary>
    procedure Clear;
    /// <summary>Von außen gesperrte Leisten (und ihre Fenster) wieder freigeben.</summary>
    procedure Enable;
    /// <summary>Die Leiste ABar wird gesperrt: Aufrufer protokollieren (im Moment des Sperrens rufen).</summary>
    procedure Disabled(ABar: TObject);
    /// <summary>False, solange die Sicherung des Features ausgelöst ist; blendet die Leisten dann einmal aus
    /// und danach wieder ein.</summary>
    function Guard: Boolean;
    property Name: string read FName;
    property Feature: TAtlasFeature read FFeature;
    /// <summary>Sind die Leisten wegen der Sicherung ausgeblendet (seit dem letzten Guard)?</summary>
    property Hidden: Boolean read FHidden;
    /// <summary>Eine Leiste ist weg (von der IDE freigegeben); nicht bei Clear.</summary>
    property OnRemoved: TProc<TControl> read FOnRemoved write FOnRemoved;
  end;

implementation

uses
  Winapi.Windows,
  Vcl.Forms,
  Atlas.IDE.Foundation.EditorBuffer;

type
  /// <summary>Nur für den Stapel im Protokoll: wird sofort wieder gefangen.</summary>
  EAtlasBarDisabled = class(Exception);

/// <summary>Steuerelement mit seinen Eltern bis zum Formular, für das Protokoll.</summary>
function ControlChain(AControl: TControl): string;
var
  mDepth: Integer;
begin
  Result := '';
  mDepth := 0;
  while (AControl <> nil) and (mDepth < 8) do
  begin
    if Result <> '' then
      Result := Result + ' < ';
    Result := Result + AControl.ClassName + ' ' + AControl.Name;
    AControl := AControl.Parent;
    Inc(mDepth);
  end;
end;

/// <summary>Fenster, die an der VCL vorbei gesperrt sind (EnableWindow), wieder freigeben; nur wo die VCL sie
/// für freigegeben hält, damit eine gewollte Sperre bleibt. False, wenn keins gesperrt war.</summary>
function EnableWindows(AControl: TWinControl): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  if not AControl.Enabled or not AControl.HandleAllocated then
    Exit;
  if not IsWindowEnabled(AControl.Handle) then
  begin
    EnableWindow(AControl.Handle, True);
    Result := True;
  end;
  for mIndex := 0 to AControl.ControlCount - 1 do
    if AControl.Controls[mIndex] is TWinControl then
      if EnableWindows(TWinControl(AControl.Controls[mIndex])) then
        Result := True;
end;

{ TAtlasEditorBarHost.TWatcher }

procedure TAtlasEditorBarHost.TWatcher.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent is TControl) and (FHost <> nil) then
    FHost.Removed(TControl(AComponent));
end;

{ TAtlasEditorBarHost }

constructor TAtlasEditorBarHost.Create(const AName: string; AFeature: TAtlasFeature; const ACreate: TCreateBar;
  const APlace: TPlaceBar);
begin
  inherited Create;
  FName := AName;
  FFeature := AFeature;
  FCreate := ACreate;
  FPlace := APlace;
  FBars := TList<TControl>.Create;
  FParents := TList<TWinControl>.Create;
  FWatcher := TWatcher.Create(nil);
  FWatcher.FHost := Self;
end;

destructor TAtlasEditorBarHost.Destroy;
begin
  Clear;
  FWatcher.Free;
  FParents.Free;
  FBars.Free;
  // Gefangene Variablen der Dienste nicht über das Ende des Hosts halten.
  FCreate := nil;
  FPlace := nil;
  FOnRemoved := nil;
  inherited Destroy;
end;

class function TAtlasEditorBarHost.EditorOf(const AWindow: INTAEditWindow): TWinControl;
var
  mEditor: TComponent;
begin
  Result := nil;
  if (AWindow = nil) or (AWindow.Form = nil) then
    Exit;
  mEditor := AWindow.Form.FindComponent('Editor');
  if (mEditor is TWinControl) and (TWinControl(mEditor).Parent <> nil) then
    Result := TWinControl(mEditor);
end;

class function TAtlasEditorBarHost.TopEditor: TWinControl;
var
  mServices: INTAEditorServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, INTAEditorServices, mServices) then
    Result := EditorOf(mServices.TopEditWindow);
end;

class procedure TAtlasEditorBarHost.FocusEditor(AControl: TControl);
var
  mForm: TCustomForm;
  mEditor: TComponent;
begin
  if AControl = nil then
    Exit;
  mForm := GetParentForm(AControl);
  if mForm = nil then
    Exit;
  mEditor := mForm.FindComponent('Editor');
  if (mEditor is TWinControl) and TWinControl(mEditor).CanFocus then
    TWinControl(mEditor).SetFocus;
end;

procedure TAtlasEditorBarHost.Removed(ABar: TControl);
var
  mIndex: Integer;
  mRemoved: TProc<TControl>;
begin
  mIndex := FBars.IndexOf(ABar);
  if mIndex < 0 then
    Exit;
  FBars.Delete(mIndex);
  FParents.Delete(mIndex);
  mRemoved := FOnRemoved;
  if Assigned(mRemoved) then
    mRemoved(ABar);
end;

procedure TAtlasEditorBarHost.Clear;
var
  mBar: TControl;
begin
  // Leisten selbst freigeben; der Wächter darf dabei nicht mehr zurückschreiben.
  FWatcher.FHost := nil;
  try
    for mBar in FBars.ToArray do
    begin
      mBar.RemoveFreeNotification(FWatcher);
      try
        mBar.Free;
      except
        on E: Exception do
          TAtlasGuard.Log(Format('%s: Leiste nicht freigegeben: %s', [FName, TAtlasGuard.SafeMessage(E.Message)]));
      end;
    end;
  finally
    FBars.Clear;
    FParents.Clear;
    FWatcher.FHost := Self;
  end;
end;

function TAtlasEditorBarHost.BarOf(AEditorParent: TWinControl): TControl;
var
  mIndex: Integer;
begin
  for mIndex := 0 to FParents.Count - 1 do
    if FParents[mIndex] = AEditorParent then
      Exit(FBars[mIndex]);
  Result := nil;
end;

function TAtlasEditorBarHost.EditorParentOf(ABar: TControl): TWinControl;
var
  mIndex: Integer;
begin
  mIndex := FBars.IndexOf(ABar);
  if mIndex < 0 then
    Exit(nil);
  Result := FParents[mIndex];
end;

function TAtlasEditorBarHost.Contains(ABar: TControl): Boolean;
begin
  Result := (ABar <> nil) and FBars.Contains(ABar);
end;

function TAtlasEditorBarHost.ActiveBar: TControl;
var
  mEditor: TWinControl;
begin
  Result := nil;
  mEditor := TopEditor;
  if mEditor <> nil then
    Result := BarOf(mEditor.Parent);
end;

function TAtlasEditorBarHost.Bars: TArray<TControl>;
begin
  Result := FBars.ToArray;
end;

function TAtlasEditorBarHost.Count: Integer;
begin
  Result := FBars.Count;
end;

/// <summary>Eigene Methode: Jede Leiste braucht ihre eigene Variable (FreeNotification, Fehlerfall).</summary>
function TAtlasEditorBarHost.CreateFor(AEditorParent: TWinControl): TControl;
var
  mBar: TControl;
begin
  Result := nil;
  mBar := nil;
  try
    mBar := FCreate(AEditorParent);
    if mBar = nil then
      Exit;
    mBar.FreeNotification(FWatcher);
    FBars.Add(mBar);
    FParents.Add(AEditorParent);
    FPlace(mBar, AEditorParent);
    Result := mBar;
  except
    on E: Exception do
    begin
      TAtlasGuard.Report(FFeature, E);
      // Halb angelegt: wieder weg, beim nächsten Takt neu.
      if (mBar <> nil) and FBars.Contains(mBar) then
        mBar.Free
      else if mBar <> nil then
      begin
        mBar.RemoveFreeNotification(FWatcher);
        mBar.Free;
      end;
    end;
  end;
end;

procedure TAtlasEditorBarHost.PlaceGuarded(ABar: TControl; AEditorParent: TWinControl);
begin
  try
    FPlace(ABar, AEditorParent);
  except
    on E: Exception do
      TAtlasGuard.Report(FFeature, E);
  end;
end;

procedure TAtlasEditorBarHost.Ensure;
var
  mServices: INTAEditorServices;
  mIndex: Integer;
  mEditor: TWinControl;
  mBar: TControl;
begin
  if not Supports(BorlandIDEServices, INTAEditorServices, mServices) then
    Exit;
  for mIndex := 0 to mServices.EditWindowCount - 1 do
  begin
    mEditor := EditorOf(mServices.EditWindow[mIndex]);
    if mEditor = nil then
      Continue;
    mBar := BarOf(mEditor.Parent);
    if mBar = nil then
      CreateFor(mEditor.Parent)
    else
      PlaceGuarded(mBar, mEditor.Parent);
  end;
  // Erst mit aktivem Editor: Während die IDE ihre Editoren schließt, gilt ihre Sperre noch.
  if TAtlasEditorBuffer.ActiveView <> nil then
    Enable;
end;

function TAtlasEditorBarHost.EnsureFor(const AWindow: INTAEditWindow): TControl;
var
  mEditor: TWinControl;
begin
  Result := nil;
  mEditor := EditorOf(AWindow);
  if mEditor = nil then
    Exit;
  Result := BarOf(mEditor.Parent);
  if Result = nil then
    Result := CreateFor(mEditor.Parent)
  else
    PlaceGuarded(Result, mEditor.Parent);
end;

procedure TAtlasEditorBarHost.ForEach(const AAction: TProc<TControl>);
var
  mBar: TControl;
begin
  for mBar in FBars.ToArray do
    try
      AAction(mBar);
    except
      on E: Exception do
        TAtlasGuard.Report(FFeature, E);
    end;
end;

procedure TAtlasEditorBarHost.Enable;
var
  mBar: TControl;
begin
  for mBar in FBars do
  begin
    if not mBar.Enabled then
    begin
      mBar.Enabled := True;
      TAtlasGuard.Log(FName + ': wieder freigegeben, ein Editor ist aktiv');
    end;
    if (mBar is TWinControl) and EnableWindows(TWinControl(mBar)) then
      TAtlasGuard.Log(FName + ': Fenster wieder freigegeben (an der VCL vorbei gesperrt)');
  end;
end;

procedure TAtlasEditorBarHost.Disabled(ABar: TObject);
var
  mTrace, mChain: string;
begin
  // Die ersten Male reichen, um den Aufrufer zu sehen.
  if FDisabledLogged >= MaxDisabledLogs then
    Exit;
  Inc(FDisabledLogged);
  mChain := '';
  if ABar is TControl then
    mChain := ControlChain(TControl(ABar).Parent);
  try
    raise EAtlasBarDisabled.Create(FName + ' wird gesperrt');
  except
    on E: Exception do
    begin
      mTrace := E.StackTrace;
      if (mTrace = '') and Assigned(TAtlasGuard.StackOf) then
        mTrace := TAtlasGuard.StackOf(E);
    end;
  end;
  TAtlasGuard.Log(Format('%s: wird gesperrt (Enabled := False), in %s; Aufrufer:%s%s',
    [FName, mChain, sLineBreak, mTrace]));
end;

procedure TAtlasEditorBarHost.Show(AShown: Boolean);
var
  mBar: TControl;
begin
  for mBar in FBars do
    if mBar.Visible <> AShown then
      mBar.Visible := AShown;
end;

function TAtlasEditorBarHost.Guard: Boolean;
begin
  Result := not TAtlasGuard.Disabled(FFeature);
  if Result = not FHidden then
    Exit;
  FHidden := not Result;
  if FHidden then
    TAtlasGuard.Log(FName + ': durch die Sicherung abgeschaltet')
  else
    TAtlasGuard.Log(FName + ': wieder eingeschaltet');
  try
    Show(Result);
  except
    // Läuft außerhalb von TAtlasGuard.Run (Feature abgeschaltet); nichts darf in die IDE durchschlagen.
    on E: Exception do
      TAtlasGuard.Log(FName + ': nicht ein- bzw. ausgeblendet: ' + TAtlasGuard.SafeMessage(E.Message));
  end;
end;

end.
