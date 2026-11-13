unit Atlas.IDE.Tests.UntestedMark;

// Marke „7 von 12 Methoden getestet“ an der unit-Zeile (#1783):
// - Stand aus der Antwort von atlas/coveredBy, die auch die Marken
//   „getestet von“ (#1778) zeichnet; nur mit Testunit und Methoden.
// - Gelb unter tests.untested.warnPercent, sonst grau.
// - Klick zeigt ein Menü mit den ungetesteten Methoden (Eintrag springt zum
//   Kopf) und „Test anlegen“ („Zur Testunit wechseln“ von Base). Gezählt
//   werden Methoden, die ein Test aufruft; das sagt der Hinweis im Menü, es
//   ist keine Abdeckungsmessung.
// Abschaltbar über codeLens.untested; ausblenden am Element (#628) je Datei.

interface

uses
  System.Types,
  Vcl.Menus,
  ToolsAPI.Editor,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Tests.CoveredBy;

type
  TAtlasIdeUntestedMark = class
  private type
    /// <summary>Lebt, solange die Marke lebt; der eingereihte Klick prüft es.</summary>
    TState = class(TInterfacedObject)
    public
      Alive: Boolean;
    end;
  private
    FState: TState;
    FStateRef: IInterface;
    FMenu: TPopupMenu;
    FFileName: string;
    /// <summary>unit-Zeile (0-basiert); -1 ohne.</summary>
    FLine: Integer;
    FUnit: TAtlasCoveredUnit;
    FListed: TArray<TAtlasCoveredMethod>;
    FRect: TRect;
    FTopRow: Integer;
    procedure PaintMark(const ARow: TRect; const AContext: INTACodeEditorPaintContext; ALeft: Integer);
    function StillShown: Boolean;
    procedure Clicked(const AAt: TPoint);
    procedure ItemClick(Sender: TObject);
    procedure CreateTestClick(Sender: TObject);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Marke zeigen? Plugin an, „Tests ausführen“ und codeLens.untested.</summary>
    class function Wanted(const ASettings: TAtlasPluginSettings): Boolean; static;
    /// <summary>Stand AUnit der Datei AFileName mit dem Text AText (für die unit-Zeile).</summary>
    procedure Update(const AFileName, AText: string; const AUnit: TAtlasCoveredUnit);
    procedure Clear;
    /// <summary>Zeile von AContext zeichnen, wenn dort die Marke steht (Einstellung, Datei, Zeile, ausgeblendet).
    /// </summary>
    procedure PaintLine(const ARow: TRect; const AContext: INTACodeEditorPaintContext);
    /// <summary>Klick an (AX, AY) im Editor auf die Marke? Dann das Menü an AAt (Bildschirm) einreihen.</summary>
    function MouseDown(AX, AY: Integer; const AAt: TPoint): Boolean;
  end;

implementation

uses
  System.SysUtils,
  Vcl.Graphics,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Editor.Elements,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Tests.Untested,
  Atlas.UI.Tests.Strings,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.Elements,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Tests.Lens;

const
  cCreateTag = -1;

{ TAtlasIdeUntestedMark }

constructor TAtlasIdeUntestedMark.Create;
begin
  inherited Create;
  FState := TState.Create;
  FState.Alive := True;
  FStateRef := FState;
  FMenu := TPopupMenu.Create(nil);
  FLine := -1;
end;

destructor TAtlasIdeUntestedMark.Destroy;
begin
  if FState <> nil then
  begin
    FState.Alive := False;
  end;
  FStateRef := nil;
  FMenu.Free;
  FListed := nil;
  inherited Destroy;
end;

class function TAtlasIdeUntestedMark.Wanted(const ASettings: TAtlasPluginSettings): Boolean;
begin
  Result := TAtlasUntested.Wanted(ASettings);
end;

procedure TAtlasIdeUntestedMark.Update(const AFileName, AText: string; const AUnit: TAtlasCoveredUnit);
begin
  FFileName := AFileName;
  FUnit := AUnit;
  FLine := TAtlasUntested.UnitLine(AText);
  FRect := TRect.Empty;
end;

procedure TAtlasIdeUntestedMark.Clear;
begin
  FFileName := '';
  FUnit := Default(TAtlasCoveredUnit);
  FLine := -1;
  FRect := TRect.Empty;
end;

procedure TAtlasIdeUntestedMark.PaintLine(const ARow: TRect; const AContext: INTACodeEditorPaintContext);
var
  mLineState: INTACodeEditorLineState;
  mLine: string;
  mRow: TRect;
  mContext: INTACodeEditorPaintContext;
begin
  if (FLine < 0) or (AContext.LogicalLineNum - 1 <> FLine) or not SameText(AContext.FileName, FFileName) or
    not TAtlasUntested.Wanted(TAtlasIdeSettings.Current) or
    not TAtlasUntested.Shown(FUnit.HasTestUnit, Length(FUnit.Methods)) then
  begin
    Exit;
  end;
  mLineState := AContext.LineState;
  if (mLineState = nil) or (AContext.EditView = nil) then
  begin
    Exit;
  end;
  mLine := mLineState.Text;
  // Text seit der Antwort verschoben: keine Marke an einer Zeile ohne „unit“.
  if Pos('unit', LowerCase(mLine)) = 0 then
  begin
    Exit;
  end;
  // Ausgeblendet am Element (#628): eine Marke je Datei, Anker ist der Name der Unit.
  if TAtlasIdeElements.Hidden(TAtlasDrawnElement.CodeLensUntested, FFileName, FUnit.UnitName) then
  begin
    FRect := TRect.Empty;
    Exit;
  end;
  mRow := ARow;
  mContext := AContext;
  TAtlasIdeLensPill.Guarded(AContext.Canvas,
    procedure
    begin
      PaintMark(mRow, mContext, TAtlasIdeLensPill.LeftOf(mContext, mLine));
    end);
end;

procedure TAtlasIdeUntestedMark.PaintMark(const ARow: TRect; const AContext: INTACodeEditorPaintContext;
  ALeft: Integer);
var
  mCanvas: TCanvas;
  mBack, mTone: TAtlasColor;
  mColors: TAtlasColors;
  mText: string;
  mTested, mTotal: Integer;
begin
  mCanvas := AContext.Canvas;
  mBack := TAtlasIdeLensPill.BackgroundAt(mCanvas, ALeft, ARow.Top + 1);
  mColors := TAtlasColors.ForBackground(mBack);
  mTested := FUnit.Tested;
  mTotal := Length(FUnit.Methods);
  mText := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.UntestedMark, [mTested, mTotal]);
  if FUnit.Incomplete then
  begin
    mText := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.CoveredByIncomplete, [mText]);
  end;
  mTone := mColors.Muted;
  if TAtlasUntested.Warn(mTested, mTotal, TAtlasIdeSettings.Current.TestsUntestedWarnPercent) then
  begin
    mTone := mColors.Warn;
  end;
  TAtlasIdeLensPill.Prepare(mCanvas, False);
  FRect := TAtlasIdeLensPill.Draw(mCanvas, ARow, mText, mTone, mBack, ALeft);
  FTopRow := AContext.EditView.TopRow;
  TAtlasIdeElements.Painted(TAtlasIdeElements.Target(TAtlasDrawnElement.CodeLensUntested, FFileName, FLine,
    FUnit.UnitName), FRect, FTopRow, ARow.Height);
end;

function TAtlasIdeUntestedMark.StillShown: Boolean;
var
  mEditors: IOTAEditorServices;
  mView: IOTAEditView;
begin
  mView := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    mView := mEditors.TopView;
  end;
  Result := (mView <> nil) and (mView.Buffer <> nil) and SameText(mView.Buffer.FileName, FFileName) and
    (mView.TopRow = FTopRow);
end;

function TAtlasIdeUntestedMark.MouseDown(AX, AY: Integer; const AAt: TPoint): Boolean;
var
  mSelf: TAtlasIdeUntestedMark;
  mState: IInterface;
  mAt: TPoint;
begin
  // Nur, wenn die Marke noch dort steht: gleiche Datei, nicht gescrollt.
  Result := not FRect.IsEmpty and PtInRect(FRect, Point(AX, AY)) and
    TAtlasUntested.Wanted(TAtlasIdeSettings.Current) and StillShown;
  if not Result then
  begin
    Exit;
  end;
  mSelf := Self;
  mState := FStateRef;
  mAt := AAt;
  // Erst nach dem Mausereignis: der Editor setzt sonst den Cursor danach.
  TAtlasMainThread.ForceQueue(TAtlasFeature.CodeLens,
    procedure
    begin
      if TState(mState as TObject).Alive then
      begin
        mSelf.Clicked(mAt);
      end;
    end);
end;

/// <summary>Menüeintrag mit ACaption (ohne Kurzwahl über &amp;); ohne AClick nur Text.</summary>
function Item(AMenu: TPopupMenu; const ACaption: string; ATag: Integer; const AClick: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(AMenu);
  Result.Caption := StringReplace(ACaption, '&', '&&', [rfReplaceAll]);
  Result.Tag := ATag;
  Result.OnClick := AClick;
  Result.Enabled := Assigned(AClick);
  AMenu.Items.Add(Result);
end;

procedure TAtlasIdeUntestedMark.Clicked(const AAt: TPoint);
var
  mMethod: TAtlasCoveredMethod;
  mIndex: Integer;
begin
  FListed := nil;
  for mMethod in FUnit.Methods do
  begin
    if Length(mMethod.Tests) = 0 then
    begin
      FListed := FListed + [mMethod];
    end;
  end;
  FMenu.Items.Clear;
  Item(FMenu, TAtlasTestsStrings.Text(TAtlasTestsTextId.UntestedListTitle), 0, nil);
  Item(FMenu, TAtlasTestsStrings.Text(TAtlasTestsTextId.UntestedListNote), 0, nil);
  Item(FMenu, '-', 0, nil);
  for mIndex := 0 to High(FListed) do
  begin
    Item(FMenu, FListed[mIndex].Name, mIndex, ItemClick);
  end;
  if Length(FListed) > 0 then
  begin
    Item(FMenu, '-', 0, nil);
  end;
  Item(FMenu, TAtlasTestsStrings.Text(TAtlasTestsTextId.UntestedCreateTest), cCreateTag, CreateTestClick);
  FMenu.Popup(AAt.X, AAt.Y);
end;

procedure TAtlasIdeUntestedMark.ItemClick(Sender: TObject);
var
  mIndex: Integer;
begin
  mIndex := (Sender as TMenuItem).Tag;
  if (mIndex >= 0) and (mIndex <= High(FListed)) then
  begin
    TAtlasIdeNavigation.GoToLocation(FFileName, FListed[mIndex].Line, FListed[mIndex].Character);
  end;
end;

procedure TAtlasIdeUntestedMark.CreateTestClick(Sender: TObject);
begin
  // Testunit öffnen bzw. anlegen wie „Zur Testunit wechseln“.
  TAtlasIdeHost.ExecuteCommand('Atlas.SwitchTestUnit');
end;

end.
