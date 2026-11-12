unit Atlas.IDE.Foundation.EditorBarDock;

// Leisten neben dem Editor-Bereich statt darin (Designer-Leisten unten im
// Formular überlagert): Im Formular-Designer reicht die Designfläche samt
// Bildlaufleisten über das ganze Eltern-Steuerelement des Editors
// („EditorPanel“), unabhängig von Leisten, die darin am Rand ausgerichtet
// sind. Leisten unten (Brotkrumenleiste der Datenbindung, Statusleiste)
// lagen deshalb unter der Bildlaufleiste, Text war abgeschnitten und
// überzeichnet. Die Designer-Leiste oben steht aus demselben Grund daneben.
// Stehen die Leisten eine Ebene höher neben dem EditorPanel, wird das
// EditorPanel selbst kleiner, und Editor wie Designer passen hinein, wie die
// IDE sie auch darin anordnet.
// - Place (über DockTop bzw. DockBottom des Leisten-Hosts) hängt eine Leiste
//   (TAtlasEditorBar mit DockOrder) oben bzw. unten neben das EditorPanel und
//   stellt alle Leisten dort in DockOrder direkt an das EditorPanel, vor die
//   Steuerelemente der IDE (Reiter oben, Statuszeile unten). Die
//   Reihenfolge rechnet TAtlasBarDock; stimmt sie schon, ändert
//   Place nichts (läuft bei jedem Takt).
// - Ohne Elternteil des EditorPanels bleibt die Leiste im EditorPanel.
// Nur im Hauptthread.

interface

uses
  Vcl.Controls,
  Atlas.Core.Editor.BarDock,
  Atlas.UI.Editor.Bar;

type
  TAtlasIdeEditorBarDock = class
  public
    /// <summary>Elternteil für Leisten neben dem Editor-Bereich: das Elternteil von AEditorParent, ohne eins
    /// AEditorParent selbst.</summary>
    class function HostOf(AEditorParent: TWinControl): TWinControl; static;
    /// <summary>ABar oben bzw. unten neben AEditorParent einhängen und die Leisten dort ordnen.</summary>
    class procedure Place(ABar: TAtlasEditorBar; AEditorParent: TWinControl; ASide: TAtlasBarSide); static;
  end;

implementation

const
  cAligns: array [TAtlasBarSide] of TAlign = (alTop, alBottom);

/// <summary>Eigene Leiste neben dem Editor (mit Platz)?</summary>
function IsDocked(AControl: TControl): Boolean;
begin
  Result := (AControl is TAtlasEditorBar) and (TAtlasEditorBar(AControl).DockOrder >= 0);
end;

/// <summary>Leisten so ordnen, wie TAtlasBarDock es rechnet; nichts tun, wenn die Reihenfolge stimmt.</summary>
procedure Arrange(AHost: TWinControl; ASide: TAtlasBarSide);
var
  mControls: TArray<TControl>;
  mItems: TArray<TAtlasBarDockItem>;
  mTops: TArray<Integer>;
  mIndex: Integer;
  mControl: TControl;
  mOwn: Boolean;
  mOrder, mCount: Integer;
begin
  SetLength(mControls, AHost.ControlCount);
  SetLength(mItems, AHost.ControlCount);
  mCount := 0;
  for mIndex := 0 to AHost.ControlCount - 1 do
  begin
    mControl := AHost.Controls[mIndex];
    if mControl.Align <> cAligns[ASide] then
    begin
      Continue;
    end;
    mOwn := IsDocked(mControl);
    // Ausgeblendete fremde richtet die VCL nicht aus; eigene ordnet Place auch ausgeblendet vor.
    if not mOwn and not mControl.Visible then
    begin
      Continue;
    end;
    mOrder := 0;
    if mOwn then
    begin
      mOrder := TAtlasEditorBar(mControl).DockOrder;
    end;
    mControls[mCount] := mControl;
    mItems[mCount] := TAtlasBarDockItem.Create(mOwn, mOrder, mControl.Top, mControl.Height);
    Inc(mCount);
  end;
  SetLength(mControls, mCount);
  SetLength(mItems, mCount);
  if TAtlasBarDock.Ordered(ASide, mItems) then
  begin
    Exit;
  end;
  mTops := TAtlasBarDock.Tops(ASide, mItems, AHost.ClientHeight);
  AHost.DisableAlign;
  try
    for mIndex := 0 to High(mControls) do
    begin
      if mItems[mIndex].Own and (mControls[mIndex].Top <> mTops[mIndex]) then
      begin
        mControls[mIndex].Top := mTops[mIndex];
      end;
    end;
  finally
    AHost.EnableAlign;
  end;
end;

{ TAtlasIdeEditorBarDock }

class function TAtlasIdeEditorBarDock.HostOf(AEditorParent: TWinControl): TWinControl;
begin
  Result := AEditorParent;
  if (AEditorParent <> nil) and (AEditorParent.Parent <> nil) then
  begin
    Result := AEditorParent.Parent;
  end;
end;

class procedure TAtlasIdeEditorBarDock.Place(ABar: TAtlasEditorBar; AEditorParent: TWinControl;
  ASide: TAtlasBarSide);
var
  mHost: TWinControl;
begin
  mHost := HostOf(AEditorParent);
  if mHost = nil then
  begin
    Exit;
  end;
  if ABar.Parent <> mHost then
  begin
    // Top vor Align und Parent: Die Reihenfolge stellt Arrange gleich danach her.
    ABar.Parent := nil;
    ABar.Align := alNone;
    ABar.Top := 0;
    if ASide = TAtlasBarSide.Bottom then
    begin
      ABar.Top := mHost.ClientHeight;
    end;
    ABar.Align := cAligns[ASide];
    ABar.Parent := mHost;
  end;
  Arrange(mHost, ASide);
end;

end.
