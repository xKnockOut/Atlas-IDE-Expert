unit Atlas.IDE.Designer.FitContainer;

// Befehl „An Inhalt anpassen“ (#742) im Menü „Anordnen“ in der IDE: jeder
// markierte Container (csAcceptsControls, TPageControl über seine aktive
// Seite), ohne Auswahl das Formular, wird an seine Kinder angepasst. Die
// Rechnung macht TAtlasFitContainer:
// - Clientgröße gegen Außengröße deckt Rahmen und BorderWidth ab; die Fläche
//   für ausgerichtete Kinder (Padding, Beschriftung der TGroupBox) liefert
//   AdjustClientRect des Containers.
// - Eine TTabSheet ändert die Größe ihres TPageControl.
// - Beim Formular setzt Atlas ClientWidth und ClientHeight, sonst die
//   Außengröße mit den Constraints des Containers.
// - Danach bekommen die Kinder ohne Align ihre Lage ausdrücklich.
// - „Anpassen rückgängig“ setzt den Stand vor dem Befehl zurück
//   (TAtlasDesignerSnapshot).
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Atlas.Core.Designer.FitContainer,
  Atlas.IDE.Designer.Snapshot,
  Atlas.IDE.Designer.Tool;

type
  TAtlasIdeFitContainer = class(TAtlasIdeDesignerTool)
  private
    FSnapshot: TAtlasDesignerSnapshot;
  public
    /// <summary>AOnMessage: Zeile in der Meldungsansicht.</summary>
    constructor Create(const AOnMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>Container unter ASelected; ohne Auswahl das Formular ARoot.</summary>
    class function Candidates(const ASelected: TArray<TComponent>; ARoot: TComponent): TArray<TWinControl>; static;
    /// <summary>Befehl ausführen; ASameWidth: alle auf die größte nötige Breite.</summary>
    procedure Execute(AMode: TAtlasFitMode; ASameWidth: Boolean);
    function CanUndo: Boolean;
    procedure Undo;
  end;

implementation

uses
  Winapi.Windows,
  System.Types,
  Vcl.Forms,
  Vcl.ComCtrls,
  ToolsAPI,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Designer.Strings,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Foundation.Settings;

const
  cDefaultPpi = 96;

type
  /// <summary>Zugang zu AdjustClientRect (geschützt in TWinControl).</summary>
  TWinControlAccess = class(TWinControl);

  /// <summary>Ein Container: Inhalt (dessen Kinder zählen) und Wirt (dessen Größe sich ändert).</summary>
  TFitTarget = record
    Content: TWinControl;
    Host: TWinControl;
    IsRoot: Boolean;
  end;

function AlignOf(AControl: TControl): TAtlasFitAlign;
begin
  case AControl.Align of
    alTop:
      Result := TAtlasFitAlign.Top;
    alBottom:
      Result := TAtlasFitAlign.Bottom;
    alLeft:
      Result := TAtlasFitAlign.Left;
    alRight:
      Result := TAtlasFitAlign.Right;
    alClient:
      Result := TAtlasFitAlign.Client;
  else
    Result := TAtlasFitAlign.None;
  end;
end;

function AnchorsOf(AControl: TControl): TAtlasFitAnchors;
begin
  Result := [];
  if akLeft in AControl.Anchors then
  begin
    Include(Result, TAtlasFitAnchor.Left);
  end;
  if akTop in AControl.Anchors then
  begin
    Include(Result, TAtlasFitAnchor.Top);
  end;
  if akRight in AControl.Anchors then
  begin
    Include(Result, TAtlasFitAnchor.Right);
  end;
  if akBottom in AControl.Anchors then
  begin
    Include(Result, TAtlasFitAnchor.Bottom);
  end;
end;

/// <summary>Abstand der Fläche für ausgerichtete Kinder vom Client (Padding, Beschriftung).</summary>
function InsetOf(AControl: TWinControl): TRect;
var
  mRect: TRect;
begin
  mRect := AControl.ClientRect;
  TWinControlAccess(AControl).AdjustClientRect(mRect);
  Result := Rect(mRect.Left, mRect.Top, AControl.ClientWidth - mRect.Right, AControl.ClientHeight - mRect.Bottom);
end;

function TargetOf(AContainer: TWinControl; ARoot: TComponent): TFitTarget;
begin
  Result.Content := AContainer;
  Result.Host := AContainer;
  Result.IsRoot := AContainer = ARoot;
  if (AContainer is TPageControl) and (TPageControl(AContainer).ActivePage <> nil) then
  begin
    Result.Content := TPageControl(AContainer).ActivePage;
  end
  else if (AContainer is TTabSheet) and (TTabSheet(AContainer).PageControl <> nil) then
  begin
    Result.Host := TTabSheet(AContainer).PageControl;
  end;
end;

function BoxOf(const ATarget: TFitTarget): TAtlasFitBox;
var
  mHost: TWinControl;
begin
  mHost := ATarget.Host;
  Result.Client := TSize.Create(ATarget.Content.ClientWidth, ATarget.Content.ClientHeight);
  Result.Outer := TSize.Create(mHost.Width, mHost.Height);
  Result.MinSize := TSize.Create(mHost.Constraints.MinWidth, mHost.Constraints.MinHeight);
  Result.MaxSize := TSize.Create(mHost.Constraints.MaxWidth, mHost.Constraints.MaxHeight);
  if ATarget.IsRoot then
  begin
    // Beim Formular zählt der Client (ClientWidth, ClientHeight).
    Result.Outer := Result.Client;
    Result.MinSize := TSize.Create(0, 0);
    Result.MaxSize := TSize.Create(0, 0);
  end;
  Result.Inset := InsetOf(ATarget.Content);
  Result.FreeWidth := ATarget.IsRoot or (mHost.Align in [alNone, alLeft, alRight, alCustom]);
  Result.FreeHeight := ATarget.IsRoot or (mHost.Align in [alNone, alTop, alBottom, alCustom]);
end;

function ChildrenOf(AContent: TWinControl; ARoot: TComponent): TArray<TControl>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to AContent.ControlCount - 1 do
  begin
    if AContent.Controls[mIndex].Owner = ARoot then
    begin
      Result := Result + [AContent.Controls[mIndex]];
    end;
  end;
end;

function FitItems(const AControls: TArray<TControl>): TArray<TAtlasFitChild>;
var
  mControl: TControl;
begin
  Result := nil;
  for mControl in AControls do
  begin
    Result := Result + [TAtlasFitChild.Create(mControl.BoundsRect, AlignOf(mControl), AnchorsOf(mControl))];
  end;
end;

procedure Apply(const ATarget: TFitTarget; const AControls: TArray<TControl>; const AResult: TAtlasFitResult);
var
  mIndex: Integer;
begin
  if ATarget.IsRoot then
  begin
    TControl(ATarget.Host).ClientWidth := AResult.Client.cx;
    TControl(ATarget.Host).ClientHeight := AResult.Client.cy;
  end
  else
  begin
    ATarget.Host.SetBounds(ATarget.Host.Left, ATarget.Host.Top, AResult.Outer.cx, AResult.Outer.cy);
  end;
  // Ausdrücklich nach der Größe: Anker hätten die Kinder sonst mitgezogen.
  for mIndex := 0 to High(AControls) do
  begin
    if AControls[mIndex].Align in [alNone, alCustom] then
    begin
      AControls[mIndex].BoundsRect := AResult.Children[mIndex];
    end;
  end;
end;

{ TAtlasIdeFitContainer }

constructor TAtlasIdeFitContainer.Create(const AOnMessage: TProc<string>);
begin
  inherited Create(AOnMessage);
  FSnapshot := TAtlasDesignerSnapshot.Create;
end;

destructor TAtlasIdeFitContainer.Destroy;
begin
  FSnapshot.Free;
  inherited Destroy;
end;

class function TAtlasIdeFitContainer.Candidates(const ASelected: TArray<TComponent>;
  ARoot: TComponent): TArray<TWinControl>;
var
  mComponent: TComponent;
begin
  Result := nil;
  if (Length(ASelected) = 0) and (ARoot is TWinControl) then
  begin
    Result := [TWinControl(ARoot)];
    Exit;
  end;
  for mComponent in ASelected do
  begin
    if (mComponent is TWinControl) and ((csAcceptsControls in TWinControl(mComponent).ControlStyle) or
      (mComponent is TPageControl)) then
    begin
      Result := Result + [TWinControl(mComponent)];
    end;
  end;
end;

/// <summary>Rechnung für alle Container; mit ASameWidth zweimal, dann alle auf die größte Breite.</summary>
function Plan(const ATargets: TArray<TFitTarget>; ARoot: TComponent; AOptions: TAtlasFitOptions;
  ASameWidth: Boolean): TArray<TAtlasFitResult>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(ATargets));
  for mIndex := 0 to High(ATargets) do
  begin
    Result[mIndex] := TAtlasFitContainer.Fit(BoxOf(ATargets[mIndex]), FitItems(ChildrenOf(ATargets[mIndex].Content,
      ARoot)), AOptions);
  end;
  if not ASameWidth then
  begin
    Exit;
  end;
  AOptions.ForceOuterWidth := TAtlasFitContainer.MaxOuterWidth(Result);
  for mIndex := 0 to High(ATargets) do
  begin
    Result[mIndex] := TAtlasFitContainer.Fit(BoxOf(ATargets[mIndex]), FitItems(ChildrenOf(ATargets[mIndex].Content,
      ARoot)), AOptions);
  end;
end;

function OptionsFor(AMode: TAtlasFitMode; ARoot: TComponent; const ASettings: TAtlasPluginSettings): TAtlasFitOptions;
var
  mPpi: Integer;
begin
  mPpi := cDefaultPpi;
  if (ARoot is TCustomForm) and (TCustomForm(ARoot).PixelsPerInch > 0) then
  begin
    mPpi := TCustomForm(ARoot).PixelsPerInch;
  end;
  Result := TAtlasFitOptions.Create(AMode, MulDiv(ASettings.DesignerFitContainerPadding, mPpi, cDefaultPpi),
    ASettings.DesignerFitContainerAlignTopLeft);
end;

procedure TAtlasIdeFitContainer.Execute(AMode: TAtlasFitMode; ASameWidth: Boolean);
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mSettings: TAtlasPluginSettings;
  mContainers: TArray<TWinControl>;
  mTargets: TArray<TFitTarget>;
  mResults: TArray<TAtlasFitResult>;
  mIndex: Integer;
  mDone: TArray<string>;
begin
  mSettings := TAtlasIdeSettings.Current;
  if not mSettings.DesignerFitContainer or not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  mContainers := Candidates(TAtlasDesignerAccess.Selection(mEditor, mRoot), mRoot);
  if (TAtlasDesignerAccess.DesignerOf(mEditor) = nil) or (Length(mContainers) = 0) then
  begin
    Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerFitContainerNone));
    Exit;
  end;
  mTargets := nil;
  for mIndex := 0 to High(mContainers) do
  begin
    mTargets := mTargets + [TargetOf(mContainers[mIndex], mRoot)];
  end;
  mResults := Plan(mTargets, mRoot, OptionsFor(AMode, mRoot, mSettings), ASameWidth);
  FSnapshot.Take(mEditor.FileName, mRoot);
  mDone := nil;
  for mIndex := 0 to High(mTargets) do
  begin
    if mResults[mIndex].OnlyClient then
    begin
      Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerFitContainerOnlyClient, [mContainers[mIndex].Name]));
      Continue;
    end;
    Apply(mTargets[mIndex], ChildrenOf(mTargets[mIndex].Content, mRoot), mResults[mIndex]);
    mDone := mDone + [Format('%s %d x %d', [mContainers[mIndex].Name, mResults[mIndex].Outer.cx,
      mResults[mIndex].Outer.cy])];
  end;
  TAtlasDesignerAccess.DesignerOf(mEditor).Modified;
  if Length(mDone) > 0 then
  begin
    Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerFitContainerDone, [string.Join(', ', mDone)]));
  end;
end;

function TAtlasIdeFitContainer.CanUndo: Boolean;
begin
  Result := FSnapshot.CanRestore;
end;

procedure TAtlasIdeFitContainer.Undo;
begin
  if FSnapshot.Restore then
  begin
    Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerFitContainerUndone));
  end;
end;

end.
