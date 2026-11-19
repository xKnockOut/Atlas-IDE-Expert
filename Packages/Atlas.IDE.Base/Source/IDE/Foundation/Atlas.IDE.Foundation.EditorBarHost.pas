unit Atlas.IDE.Foundation.EditorBarHost;

// Gemeinsamer Leisten-Host (#1248). Jede Leiste im Editor (Editorleiste,
// Statusleiste, Brotkrumen, Übersichtsleiste, Minimap, Suchleiste) braucht
// dieselbe Verwaltung; eine Kopie je Dienst hätte jeden Fehler mehrfach
// (etwa die Suchleiste, die die IDE nach dem Projektwechsel sperrt). Der
// Host übernimmt:
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
// - Sperren protokollieren: Disabled und Enable schreiben je Host nur die
//   erste Sperre und Freigabe als eine Zeile. Der Verursacher ist bekannt
//   (TEditWindow.ShowView beim Tab-Wechsel und Schließen aller Editoren,
//   2.0-stable); ein Stapel je Sperre füllte nur das Protokoll.
// - Thema: ForEach wendet Farben (oder anderes) auf jede Leiste an.
// - Absturzsicherung je Leiste: Anlegen, Einordnen und ForEach laufen je
//   Leiste in einem eigenen try; ein Fehler zählt für das Feature
//   (TAtlasGuard.Report), die übrigen Leisten laufen weiter. Guard blendet
//   die Leisten aus, solange die Sicherung des Features ausgelöst ist, und
//   danach wieder ein.
// - Platz und Ansicht (#1442) stehen in Placement (TAtlasEditorBarPlacement):
//   Einordnen über den Haken Place oder neben dem Editor-Bereich (DockTop,
//   DockBottom), nur im Code-Editor, nur im Designer oder in beiden (ShowIn);
//   Ensure ordnet ein und blendet danach ein und aus.
// - Das Editor-Steuerelement eines Fensters sucht TAtlasIdeEditorWindows.
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
  Atlas.Core.Diagnostics.Guard,
  Atlas.IDE.Foundation.EditorBarPlacement;

type
{$SCOPEDENUMS ON}
  /// <summary>Was ein Leisten-Host schon protokolliert hat: erste Sperre, erste Freigabe.</summary>
  TAtlasEditorBarLogged = (Disabled, Enabled);
{$SCOPEDENUMS OFF}

  /// <summary>In welcher Ansicht des Editorfensters die Leiste erscheint (für Aufrufer ohne Placement).</summary>
  TAtlasEditorBarView = Atlas.IDE.Foundation.EditorBarPlacement.TAtlasEditorBarView;

  TAtlasEditorBarHost = class
  public type
    /// <summary>Neue Leiste für das Eltern-Steuerelement des Editors; noch ohne Parent.</summary>
    TCreateBar = reference to function(AEditorParent: TWinControl): TControl;
    /// <summary>Leiste einordnen (Parent, Align, Reihenfolge); beim Anlegen und bei jedem Ensure.</summary>
    TPlaceBar = TAtlasEditorBarPlacement.TPlaceBar;
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
    FPlacement: TAtlasEditorBarPlacement;
    FWatcher: TWatcher;
    FBars: TList<TControl>;
    /// <summary>Eltern-Steuerelement des Editors je Leiste (gleicher Index wie FBars).</summary>
    FParents: TList<TWinControl>;
    FHidden: Boolean;
    /// <summary>Erste Sperre bzw. Freigabe schon protokolliert; danach still.</summary>
    FLogged: set of TAtlasEditorBarLogged;
    FOnRemoved: TProc<TControl>;
    procedure Removed(ABar: TControl);
    function CreateFor(AEditorParent: TWinControl): TControl;
    /// <summary>Einordnen und nach der Ansicht ein- bzw. ausblenden, je Leiste abgesichert.</summary>
    procedure PlaceGuarded(ABar: TControl; AEditorParent: TWinControl);
    /// <summary>Leisten ein- bzw. ausblenden; eingeblendet wird nur, was zur Ansicht passt.</summary>
    procedure ShowBars(AShown: Boolean);
  public
    /// <summary>AName steht im Protokoll („Editorleiste“); AFeature ist die Sicherung der Leisten. APlace darf
    /// nil sein, wenn DockTop bzw. DockBottom einordnen.</summary>
    constructor Create(const AName: string; AFeature: TAtlasFeature; const ACreate: TCreateBar;
      const APlace: TPlaceBar);
    destructor Destroy; override;
    /// <summary>Für jedes Editorfenster die Leiste anlegen bzw. einordnen; danach gesperrte freigeben, wenn ein
    /// Editor aktiv ist.</summary>
    procedure Ensure;
    /// <summary>Leiste für ein Editorfenster anlegen bzw. einordnen; nil ohne Editor oder bei Fehler.</summary>
    function EnsureFor(const AWindow: INTAEditWindow): TControl;
    /// <summary>Leiste zum Eltern-Steuerelement des Editors; nil ohne.</summary>
    function BarOf(AEditorParent: TWinControl): TControl;
    /// <summary>Leiste des vordersten Editorfensters; nil ohne.</summary>
    function ActiveBar: TControl;
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
    /// <summary>Platz und Ansicht der Leisten (DockTop, DockBottom, ShowIn); gilt ab dem nächsten Ensure.
    /// </summary>
    property Placement: TAtlasEditorBarPlacement read FPlacement;
    /// <summary>Steht die Leiste ABar gerade sichtbar im Editorfenster (nach Ansicht und Sicherung)?</summary>
    function Showing(ABar: TControl): Boolean;
  end;

implementation

uses
  Winapi.Windows,
  Atlas.IDE.Foundation.EditorWindows,
  Atlas.IDE.Foundation.EditorBuffer;

/// <summary>Fenster, die an der VCL vorbei gesperrt sind (EnableWindow), wieder freigeben; nur wo die VCL sie
/// für freigegeben hält, damit eine gewollte Sperre bleibt. False, wenn keins gesperrt war.</summary>
function EnableWindows(AControl: TWinControl): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  if not AControl.Enabled or not AControl.HandleAllocated then
  begin
    Exit;
  end;
  if not IsWindowEnabled(AControl.Handle) then
  begin
    EnableWindow(AControl.Handle, True);
    Result := True;
  end;
  for mIndex := 0 to AControl.ControlCount - 1 do
  begin
    if AControl.Controls[mIndex] is TWinControl then
    begin
      if EnableWindows(TWinControl(AControl.Controls[mIndex])) then
      begin
        Result := True;
      end;
    end;
  end;
end;

{ TAtlasEditorBarHost.TWatcher }

procedure TAtlasEditorBarHost.TWatcher.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent is TControl) and (FHost <> nil) then
  begin
    FHost.Removed(TControl(AComponent));
  end;
end;

{ TAtlasEditorBarHost }

constructor TAtlasEditorBarHost.Create(const AName: string; AFeature: TAtlasFeature; const ACreate: TCreateBar;
  const APlace: TPlaceBar);
begin
  inherited Create;
  FName := AName;
  FFeature := AFeature;
  FCreate := ACreate;
  FPlacement := TAtlasEditorBarPlacement.Create(APlace);
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
  FPlacement.Free;
  // Gefangene Variablen der Dienste nicht über das Ende des Hosts halten.
  FCreate := nil;
  FOnRemoved := nil;
  inherited Destroy;
end;

procedure TAtlasEditorBarHost.Removed(ABar: TControl);
var
  mIndex: Integer;
  mRemoved: TProc<TControl>;
begin
  mIndex := FBars.IndexOf(ABar);
  if mIndex < 0 then
  begin
    Exit;
  end;
  FBars.Delete(mIndex);
  FParents.Delete(mIndex);
  mRemoved := FOnRemoved;
  if Assigned(mRemoved) then
  begin
    mRemoved(ABar);
  end;
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
    begin
      Exit;
    end;
    mBar.FreeNotification(FWatcher);
    FBars.Add(mBar);
    FParents.Add(AEditorParent);
    FPlacement.Place(mBar, AEditorParent);
    FPlacement.Apply(mBar, AEditorParent, FHidden);
    Result := mBar;
  except
    on E: Exception do
    begin
      TAtlasGuard.Report(FFeature, E);
      // Halb angelegt: wieder weg, beim nächsten Takt neu.
      if (mBar <> nil) and FBars.Contains(mBar) then
      begin
        mBar.Free;
      end
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
    FPlacement.Place(ABar, AEditorParent);
    FPlacement.Apply(ABar, AEditorParent, FHidden);
  except
    on E: Exception do
      TAtlasGuard.Report(FFeature, E);
  end;
end;

procedure TAtlasEditorBarHost.ShowBars(AShown: Boolean);
var
  mIndex: Integer;
begin
  // Eingeblendet wird nur, was zur Ansicht passt (Code bzw. Designer).
  for mIndex := 0 to FBars.Count - 1 do
  begin
    if AShown and (FPlacement.ShowIn <> TAtlasEditorBarView.Any) then
    begin
      FPlacement.Apply(FBars[mIndex], FParents[mIndex], FHidden);
    end
    else if FBars[mIndex].Visible <> AShown then
    begin
      FBars[mIndex].Visible := AShown;
    end;
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
  begin
    Exit;
  end;
  for mIndex := 0 to mServices.EditWindowCount - 1 do
  begin
    mEditor := TAtlasIdeEditorWindows.EditorOf(mServices.EditWindow[mIndex]);
    if mEditor = nil then
    begin
      Continue;
    end;
    mBar := BarOf(mEditor.Parent);
    if mBar = nil then
    begin
      CreateFor(mEditor.Parent);
    end
    else
    begin
      PlaceGuarded(mBar, mEditor.Parent);
    end;
  end;
  // Erst mit aktivem Editor: Während die IDE ihre Editoren schließt, gilt ihre Sperre noch.
  if TAtlasEditorBuffer.ActiveView <> nil then
  begin
    Enable;
  end;
end;

function TAtlasEditorBarHost.EnsureFor(const AWindow: INTAEditWindow): TControl;
var
  mEditor: TWinControl;
begin
  Result := nil;
  mEditor := TAtlasIdeEditorWindows.EditorOf(AWindow);
  if mEditor = nil then
  begin
    Exit;
  end;
  Result := BarOf(mEditor.Parent);
  if Result = nil then
  begin
    Result := CreateFor(mEditor.Parent);
  end
  else
  begin
    PlaceGuarded(Result, mEditor.Parent);
  end;
end;

function TAtlasEditorBarHost.BarOf(AEditorParent: TWinControl): TControl;
var
  mIndex: Integer;
begin
  for mIndex := 0 to FParents.Count - 1 do
  begin
    if FParents[mIndex] = AEditorParent then
    begin
      Exit(FBars[mIndex]);
    end;
  end;
  Result := nil;
end;

function TAtlasEditorBarHost.ActiveBar: TControl;
var
  mEditor: TWinControl;
begin
  Result := nil;
  mEditor := TAtlasIdeEditorWindows.TopEditor;
  if mEditor <> nil then
  begin
    Result := BarOf(mEditor.Parent);
  end;
end;

function TAtlasEditorBarHost.Contains(ABar: TControl): Boolean;
begin
  Result := (ABar <> nil) and FBars.Contains(ABar);
end;

function TAtlasEditorBarHost.Bars: TArray<TControl>;
begin
  Result := FBars.ToArray;
end;

function TAtlasEditorBarHost.Count: Integer;
begin
  Result := FBars.Count;
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
          TAtlasGuard.Log(Format('%s: Leiste nicht freigegeben: %s', [FName, TAtlasGuard.MessageText(E.Message)]));
      end;
    end;
  finally
    FBars.Clear;
    FParents.Clear;
    FWatcher.FHost := Self;
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
      if not (TAtlasEditorBarLogged.Enabled in FLogged) then
      begin
        Include(FLogged, TAtlasEditorBarLogged.Enabled);
        TAtlasGuard.Log(FName + ': wieder freigegeben, ein Editor ist aktiv (weitere Freigaben ohne Protokoll)');
      end;
    end;
    if (mBar is TWinControl) and EnableWindows(TWinControl(mBar)) then
    begin
      TAtlasGuard.Log(FName + ': Fenster wieder freigegeben (an der VCL vorbei gesperrt)');
    end;
  end;
end;

procedure TAtlasEditorBarHost.Disabled(ABar: TObject);
var
  mChain: string;
begin
  // Die IDE sperrt die Leisten bei jedem Tab-Wechsel (TEditWindow.ShowView); Enable gibt sie wieder frei.
  if TAtlasEditorBarLogged.Disabled in FLogged then
  begin
    Exit;
  end;
  Include(FLogged, TAtlasEditorBarLogged.Disabled);
  mChain := '';
  if ABar is TControl then
  begin
    mChain := TAtlasIdeEditorWindows.ParentChain(TControl(ABar).Parent);
  end;
  TAtlasGuard.Log(Format('%s: gesperrt (Enabled := False), in %s; weitere Sperren ohne Protokoll',
    [FName, mChain]));
end;

function TAtlasEditorBarHost.Guard: Boolean;
begin
  Result := not TAtlasGuard.Disabled(FFeature);
  if Result = not FHidden then
  begin
    Exit;
  end;
  FHidden := not Result;
  if FHidden then
  begin
    TAtlasGuard.Log(FName + ': durch die Sicherung abgeschaltet');
  end
  else
  begin
    TAtlasGuard.Log(FName + ': wieder eingeschaltet');
  end;
  try
    ShowBars(Result);
  except
    // Läuft außerhalb von TAtlasGuard.Run (Feature abgeschaltet); nichts darf in die IDE durchschlagen.
    on E: Exception do
      TAtlasGuard.Log(FName + ': nicht ein- bzw. ausgeblendet: ' + TAtlasGuard.MessageText(E.Message));
  end;
end;

function TAtlasEditorBarHost.Showing(ABar: TControl): Boolean;
begin
  Result := Contains(ABar) and ABar.Visible;
end;

end.
