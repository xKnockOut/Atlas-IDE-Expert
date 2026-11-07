unit Atlas.IDE.Tracker.CodeLinkMarks;

// Markierung und Hover der Issue-Kennungen im Editor (#1265), Teil von
// Atlas.IDE.Tracker.CodeLinks:
// - TAtlasCodeLinkPainter unterstreicht die Kennungen einer gezeichneten Zeile
//   gepunktet und liefert, wo sie stehen (TAtlasCodeLinkHit).
// - TAtlasCodeLinkHover zeigt nach TAtlasCloseRules.cTooltipShowDelayMs die
//   Kurzvorschau: Stand aus dem Zwischenspeicher der Vorschau (Peek), sonst
//   „Wird geladen …“ und eine Kurzabfrage im Hintergrund (Lookup); ein Stand
//   älter als TAtlasIdeIssueLookups.FreshMs wird dabei aufgefrischt.
// Gesichert über TAtlasFeature.IssueLinks (#493). Nur im Hauptthread.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Types,
  ToolsAPI.Editor,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.CodeLinks,
  Atlas.UI.Popup.TitledTip,
  Atlas.UI.Tracker.IssueTip,
  Atlas.IDE.Tracker.IssuePreview;

type
  /// <summary>Gezeichnete Kennung (Koordinaten des Editors).</summary>
  TAtlasCodeLinkHit = record
    Wnd: HWND;
    FileName: string;
    /// <summary>0-basiert.</summary>
    Line: Integer;
    TopRow: Integer;
    Rect: TRect;
    Match: TAtlasIssueKeyMatch;
  end;

  /// <summary>Unterstreicht die Kennungen einer Zeile des Editors.</summary>
  TAtlasCodeLinkPainter = class
  public const
    /// <summary>Anteil der Akzentfarbe an der Unterstreichung (Rest: Hintergrund).</summary>
    LineStrength = 0.75;
  public
    /// <summary>AText: Zeile des Stands; ATabWidth: Tabulatorweite des Puffers. Ergebnis: die gezeichneten
    /// Kennungen.</summary>
    class function Paint(const ARect: TRect; const AContext: INTACodeEditorPaintContext; const AText: string;
      const AMatches: TArray<TAtlasIssueKeyMatch>; ATabWidth: Integer): TArray<TAtlasCodeLinkHit>; static;
  end;

  /// <summary>Kurzvorschau über einer Kennung.</summary>
  TAtlasCodeLinkHover = class
  private class var
    FInstance: TAtlasCodeLinkHover;
    FSerial: Integer;
  private
    FPreview: TFunc<TAtlasIdeIssuePreview>;
    FSerialOf: Integer;
    FTip: TAtlasTitledTip;
    FHit: TAtlasCodeLinkHit;
    FOn: Boolean;
    FSince: UInt64;
    FScreen: TRect;
    FTipKey: string;
    FTarget: TAtlasTrackerTarget;
    function Preview: TAtlasIdeIssuePreview;
    procedure ShowTip;
    procedure ShowState(const AKey: string; AState: TAtlasIssueTipState; const ADetails: TAtlasTrackerDetails;
      AError: TAtlasCiFetchError);
    procedure LookedUp(const AKey: string; ASucceeded: Boolean; const ADetails: TAtlasTrackerDetails;
      AError: TAtlasCiFetchError);
  public
    /// <summary>APreview: Vorschau-Steuerung (Zwischenspeicher, Kurzabfrage); liefert nil ohne.</summary>
    constructor Create(const APreview: TFunc<TAtlasIdeIssuePreview>);
    destructor Destroy; override;
    /// <summary>Maus über AHit (AOn) bzw. über keiner Kennung; eine andere Kennung schließt den Tooltip.</summary>
    procedure SetHit(const AHit: TAtlasCodeLinkHit; AOn: Boolean);
    /// <summary>Lage der Kennung auf dem Bildschirm.</summary>
    procedure SetScreen(const ARect: TRect);
    /// <summary>Takt: Tooltip zeigen, wenn die Maus lange genug da ist, schließen, wenn sie weg ist.
    /// ATarget: Tracker des Stands.</summary>
    procedure Check(AShown: Boolean; const ATarget: TAtlasTrackerTarget);
    procedure Hide;
    /// <summary>Liegt APoint (Bildschirm) über dem offenen Tooltip?</summary>
    function Over(const APoint: TPoint): Boolean;
    property Hovering: Boolean read FOn;
  end;

implementation

uses
  System.Classes,
  System.Math,
  System.DateUtils,
  Vcl.Controls,
  Vcl.Graphics,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Editor.CloseRules,
  Atlas.Core.Lsp.Session,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Tracker.IssueLookups;

{ TAtlasCodeLinkPainter }

/// <summary>Gepunktet wie die Links des Editors: jeder zweite Pixel von AFrom bis vor ATo.</summary>
procedure DotLine(ADC: HDC; AFrom, ATo, AY: Integer; AColor: COLORREF);
var
  mX: Integer;
begin
  mX := AFrom;
  while mX < ATo do
  begin
    SetPixel(ADC, mX, AY, AColor);
    Inc(mX, 2);
  end;
end;

class function TAtlasCodeLinkPainter.Paint(const ARect: TRect; const AContext: INTACodeEditorPaintContext;
  const AText: string; const AMatches: TArray<TAtlasIssueKeyMatch>; ATabWidth: Integer): TArray<TAtlasCodeLinkHit>;
var
  mMatch: TAtlasIssueKeyMatch;
  mFirst, mLast, mCode: TRect;
  mBack: TAtlasColor;
  mColor: COLORREF;
  mDC: HDC;
  mSaved: Integer;
  mHit: TAtlasCodeLinkHit;
begin
  Result := nil;
  mBack := TAtlasIdeStyle.SampleBack(AContext.Canvas, ARect.Right - 2, ARect.Top + 1);
  mColor := COLORREF(ColorToRGB(TColor(TAtlasColorMath.Mix(TAtlasColors.ForBackground(mBack).Accent, mBack,
    LineStrength))));
  mDC := AContext.Canvas.Handle;
  mCode := AContext.LineState.CodeRect;
  mSaved := SaveDC(mDC);
  try
    if mCode.Right > mCode.Left then
    begin
      IntersectClipRect(mDC, mCode.Left, ARect.Top, ARect.Right, ARect.Bottom);
    end;
    for mMatch in AMatches do
    begin
      mFirst := AContext.EditorState.GetCharacterPosPx(TLspSession.IndexToColumn(AText, mMatch.Character, ATabWidth),
        AContext.EditorLineNum);
      mLast := AContext.EditorState.GetCharacterPosPx(
        TLspSession.IndexToColumn(AText, mMatch.Character + mMatch.Length, ATabWidth), AContext.EditorLineNum);
      DotLine(mDC, mFirst.Left, mLast.Left, ARect.Bottom - 2, mColor);
      mHit := Default(TAtlasCodeLinkHit);
      mHit.Wnd := AContext.EditControl.Handle;
      mHit.FileName := AContext.FileName;
      mHit.Line := AContext.LogicalLineNum - 1;
      mHit.TopRow := AContext.EditView.TopRow;
      mHit.Rect := TRect.Create(mFirst.Left, ARect.Top, Max(mLast.Left, mFirst.Left + 1), ARect.Bottom);
      mHit.Match := mMatch;
      Result := Result + [mHit];
    end;
  finally
    RestoreDC(mDC, mSaved);
  end;
end;

{ TAtlasCodeLinkHover }

constructor TAtlasCodeLinkHover.Create(const APreview: TFunc<TAtlasIdeIssuePreview>);
begin
  inherited Create;
  FPreview := APreview;
  Inc(FSerial);
  FSerialOf := FSerial;
  FInstance := Self;
  FTip := TAtlasTitledTip.Create(nil);
  FTip.GuardFeature := TAtlasFeature.IssueLinks;
end;

destructor TAtlasCodeLinkHover.Destroy;
begin
  if FInstance = Self then
  begin
    FInstance := nil;
  end;
  FreeAndNil(FTip);
  FHit := Default(TAtlasCodeLinkHit);
  FPreview := nil;
  FTipKey := '';
  inherited Destroy;
end;

function TAtlasCodeLinkHover.Preview: TAtlasIdeIssuePreview;
begin
  Result := nil;
  if Assigned(FPreview) then
  begin
    Result := FPreview();
  end;
end;

function TAtlasCodeLinkHover.Over(const APoint: TPoint): Boolean;
begin
  Result := (FTip <> nil) and FTip.IsShown and PtInRect(FTip.BoundsRect, APoint);
end;

procedure TAtlasCodeLinkHover.SetScreen(const ARect: TRect);
begin
  FScreen := ARect;
end;

procedure TAtlasCodeLinkHover.SetHit(const AHit: TAtlasCodeLinkHit; AOn: Boolean);
var
  mChanged: Boolean;
begin
  mChanged := AOn <> FOn;
  if AOn and FOn then
  begin
    mChanged := (AHit.Wnd <> FHit.Wnd) or (AHit.Line <> FHit.Line) or
      (AHit.Match.Character <> FHit.Match.Character) or not SameText(AHit.FileName, FHit.FileName);
  end;
  if not mChanged then
  begin
    Exit;
  end;
  Hide;
  FOn := AOn;
  FHit := AHit;
  FSince := TThread.GetTickCount64;
end;

procedure TAtlasCodeLinkHover.Check(AShown: Boolean; const ATarget: TAtlasTrackerTarget);
begin
  if not FOn then
  begin
    Exit;
  end;
  // Kein Stand mehr, oder die Maus hat die Kennung verlassen, ohne dass der Editor es gemeldet hat (anderes
  // Fenster).
  if not AShown or (not PtInRect(FScreen, Mouse.CursorPos) and not Over(Mouse.CursorPos)) then
  begin
    SetHit(Default(TAtlasCodeLinkHit), False);
  end
  else if not FTip.IsShown and (TThread.GetTickCount64 - FSince >= TAtlasCloseRules.cTooltipShowDelayMs) then
  begin
    FTarget := ATarget;
    ShowTip;
  end;
end;

procedure TAtlasCodeLinkHover.Hide;
begin
  FTipKey := '';
  if (FTip <> nil) and FTip.IsShown then
  begin
    FTip.HidePopup;
  end;
end;

procedure TAtlasCodeLinkHover.ShowState(const AKey: string; AState: TAtlasIssueTipState;
  const ADetails: TAtlasTrackerDetails; AError: TAtlasCiFetchError);
var
  mText: string;
begin
  mText := TAtlasIssueTip.Compose(AKey, AState, ADetails, AError, TTimeZone.Local.ToUniversalTime(Now),
    TAtlasIdeIssuePreview.Active);
  FTipKey := AKey;
  FTip.ShowNote(AKey, mText, Point(FScreen.Left, FScreen.Bottom + 2));
end;

procedure TAtlasCodeLinkHover.ShowTip;
var
  mPreview: TAtlasIdeIssuePreview;
  mTarget: TAtlasTrackerTarget;
  mDetails: TAtlasTrackerDetails;
  mKey: string;
  mSerial: Integer;
  mCached: Boolean;
begin
  mPreview := Preview;
  if mPreview = nil then
  begin
    Exit;
  end;
  mTarget := FHit.Match.IssueTarget(FTarget);
  mCached := mPreview.Lookups.Peek(mTarget, FHit.Match.IssueKey, mDetails);
  if mCached then
  begin
    ShowState(FHit.Match.Key, TAtlasIssueTipState.Found, mDetails, TAtlasCiFetchError.None);
  end
  else
  begin
    ShowState(FHit.Match.Key, TAtlasIssueTipState.Loading, mDetails, TAtlasCiFetchError.None);
  end;
  // Erst der Hover fragt; ein frischer Stand braucht keine Abfrage.
  if mCached and TAtlasIdeIssueLookups.Fresh(mDetails) then
  begin
    Exit;
  end;
  mSerial := FSerialOf;
  mKey := FHit.Match.Key;
  mPreview.Lookups.Lookup(mTarget, FHit.Match.IssueKey,
    procedure(ASucceeded: Boolean; const ADetails: TAtlasTrackerDetails; AError: TAtlasCiFetchError)
    begin
      if (FInstance <> nil) and (FInstance.FSerialOf = mSerial) then
      begin
        FInstance.LookedUp(mKey, ASucceeded, ADetails, AError);
      end;
    end);
end;

procedure TAtlasCodeLinkHover.LookedUp(const AKey: string; ASucceeded: Boolean; const ADetails: TAtlasTrackerDetails;
  AError: TAtlasCiFetchError);
var
  mCached: TAtlasTrackerDetails;
begin
  // Nur, solange der Tooltip noch diese Kennung zeigt.
  if not FOn or not FTip.IsShown or (FTipKey <> AKey) then
  begin
    Exit;
  end;
  if ASucceeded then
  begin
    ShowState(AKey, TAtlasIssueTipState.Found, ADetails, AError);
  end
  else if AError = TAtlasCiFetchError.NotFound then
  begin
    ShowState(AKey, TAtlasIssueTipState.NotFound, ADetails, AError);
  end
  else if not ((Preview <> nil) and Preview.Lookups.Peek(FHit.Match.IssueTarget(FTarget), FHit.Match.IssueKey, mCached)) then
  begin
    // Ohne Netz bleibt ein vorhandener Stand stehen; sonst der Grund.
    ShowState(AKey, TAtlasIssueTipState.Failed, ADetails, AError);
  end;
end;

end.
