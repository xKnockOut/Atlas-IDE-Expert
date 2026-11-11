unit Atlas.IDE.Search.Painter;

// Atlas-Suche im Editor (#877, #1227): rahmt die Treffer der letzten Suche (TAtlasIdeSearchSession) im
// Code-Editor über einen Zeichen-Notifier der IDE. Gerechnet wird je Datei, Suche und Text einmal, bei Bereich
// Methode zusätzlich je Cursorzeile. Zeichnen darf die IDE nie stören: Fehler gehen an TAtlasGuard.

interface

uses
  System.Types,
  Vcl.Controls,
  ToolsAPI.Editor,
  Atlas.Core.Search.Matching;

type
  TAtlasIdeSearchPainter = class
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedLineStages: TPaintLineStages; override;
    end;
  private
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FCheck: Boolean;
    FKey: string;
    FLines: TArray<string>;
    FTabWidth: Integer;
    // Je 0-basierter Zeile die Treffer.
    FHits: TArray<TArray<TAtlasSearchHit>>;
    procedure BeginPaint(const Editor: TWinControl; const ForceFullRepaint: Boolean);
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    procedure Refresh(const AContext: INTACodeEditorPaintContext);
    /// <summary>Treffer neu suchen, wenn sich Datei, Suche, Text oder (Methode) Cursorzeile geändert haben.</summary>
    procedure Recompute(const AContext: INTACodeEditorPaintContext; const AText: string);
    /// <summary>Hat die Zeile Treffer, und passt die gezeichnete Zeile zum berechneten Text?</summary>
    function HasHits(ALine: Integer; const AContext: INTACodeEditorPaintContext): Boolean;
    procedure DrawHits(ALine: Integer; const ARect: TRect; const AContext: INTACodeEditorPaintContext);
  public
    constructor Create;
    destructor Destroy; override;
  end;

implementation

uses
  System.SysUtils,
  Winapi.Windows,
  Vcl.Graphics,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Editor.Pairs,
  Atlas.Text.Lines,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Search.Editor,
  Atlas.IDE.Search.Session;

{ TAtlasIdeSearchPainter.TEvents }

function TAtlasIdeSearchPainter.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevBeginEndPaintEvents, cevPaintLineEvents];
end;

function TAtlasIdeSearchPainter.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TAtlasIdeSearchPainter }

constructor TAtlasIdeSearchPainter.Create;
var
  mServices: INTACodeEditorServices;
begin
  inherited Create;
  FIndex := -1;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorBeginPaint := BeginPaint;
  FEvents.OnEditorPaintLine := PaintLine;
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    FIndex := mServices.AddEditorEventsNotifier(FEventsRef);
  end;
end;

destructor TAtlasIdeSearchPainter.Destroy;
var
  mServices: INTACodeEditorServices;
begin
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    mServices.RemoveEditorEventsNotifier(FIndex);
  end;
  FEvents.OnEditorBeginPaint := nil;
  FEvents.OnEditorPaintLine := nil;
  FEventsRef := nil;
  inherited Destroy;
end;

procedure TAtlasIdeSearchPainter.BeginPaint(const Editor: TWinControl; const ForceFullRepaint: Boolean);
begin
  FCheck := True;
end;

procedure TAtlasIdeSearchPainter.Refresh(const AContext: INTACodeEditorPaintContext);
var
  mView: IOTAEditView;
begin
  FCheck := False;
  mView := AContext.EditView;
  if (mView = nil) or (mView.Buffer = nil) or TAtlasIdeSearchSession.Last.IsEmpty then
  begin
    FHits := nil;
    FKey := '';
    Exit;
  end;
  Recompute(AContext, TAtlasEditorBuffer.Text(mView.Buffer));
end;

procedure TAtlasIdeSearchPainter.Recompute(const AContext: INTACodeEditorPaintContext; const AText: string);
var
  mView: IOTAEditView;
  mKey: string;
  mArea: TAtlasSearchArea;
  mHit: TAtlasSearchHit;
  mQuery: TAtlasSearchQuery;
begin
  mView := AContext.EditView;
  mQuery := TAtlasIdeSearchSession.Last;
  FLines := TTextLines.SplitLines(AText);
  // Bei Bereich Methode hängt die Hervorhebung am Cursor; der wandert, also gehört er zum Schlüssel. Sonst nicht:
  // Jede Cursorzeile suchte die ganze Unit neu (#1227).
  mKey := AContext.FileName + #0 + IntToStr(TAtlasIdeSearchSession.Version) + #0 + AText;
  if mQuery.Scope = TAtlasSearchScope.Method then
  begin
    mKey := IntToStr(mView.CursorPos.Line) + #0 + mKey;
  end;
  if mKey = FKey then
  begin
    Exit;
  end;
  FKey := mKey;
  FHits := nil;
  SetLength(FHits, Length(FLines));
  FTabWidth := TAtlasEditorBuffer.TabWidth(mView.Buffer);
  if not TAtlasIdeSearchEditor.AreaOf(AText, mQuery, TAtlasIdeSearchEditor.CursorOf(mView, FLines), mArea) then
  begin
    Exit;
  end;
  for mHit in TAtlasTextSearch.FindAll(FLines, mQuery.Text, mQuery.Options, mArea) do
  begin
    if mHit.Line <= High(FHits) then
    begin
      FHits[mHit.Line] := FHits[mHit.Line] + [mHit];
    end;
  end;
end;

function TAtlasIdeSearchPainter.HasHits(ALine: Integer; const AContext: INTACodeEditorPaintContext): Boolean;
var
  mLineState: INTACodeEditorLineState;
begin
  Result := False;
  if (ALine < 0) or (ALine > High(FHits)) or (Length(FHits[ALine]) = 0) then
  begin
    Exit;
  end;
  // Nur, wenn die gezeichnete Zeile zum berechneten Text passt.
  mLineState := AContext.LineState;
  Result := (mLineState <> nil) and (TrimRight(mLineState.Text) = TrimRight(FLines[ALine]));
end;

procedure TAtlasIdeSearchPainter.DrawHits(ALine: Integer; const ARect: TRect;
  const AContext: INTACodeEditorPaintContext);
var
  mFirst, mLast: Integer;
  mHit: TAtlasSearchHit;
  mCell, mLastCell: TRect;
  mDC: HDC;
  mSaved: Integer;
  mPen, mOld, mBrush: HGDIOBJ;
begin
  mDC := AContext.Canvas.Handle;
  mSaved := SaveDC(mDC);
  try
    mPen := CreatePen(PS_SOLID, 1, ColorToRGB(TColor(TAtlasIdeStyle.Colors.Warn)));
    mOld := SelectObject(mDC, mPen);
    mBrush := SelectObject(mDC, GetStockObject(NULL_BRUSH));
    try
      for mHit in FHits[ALine] do
      begin
        mFirst := TAtlasPairs.ColumnOf(FLines[ALine], mHit.Character, FTabWidth);
        mLast := TAtlasPairs.ColumnOf(FLines[ALine], mHit.Character + mHit.Length - 1, FTabWidth);
        mCell := AContext.EditorState.GetCharacterPosPx(mFirst, AContext.EditorLineNum);
        mLastCell := AContext.EditorState.GetCharacterPosPx(mLast, AContext.EditorLineNum);
        Winapi.Windows.Rectangle(mDC, mCell.Left, ARect.Top, mLastCell.Right, ARect.Bottom);
      end;
    finally
      SelectObject(mDC, mBrush);
      SelectObject(mDC, mOld);
      DeleteObject(mPen);
    end;
  finally
    RestoreDC(mDC, mSaved);
  end;
end;

procedure TAtlasIdeSearchPainter.PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  mLine: Integer;
begin
  if TAtlasGuard.Disabled(TAtlasFeature.Search) then
  begin
    Exit;
  end;
  if BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) or not TAtlasIdeSearchSession.Highlight or
    TAtlasIdeSearchSession.Last.IsEmpty then
  begin
    Exit;
  end;
  try
    if FCheck then
    begin
      Refresh(Context);
    end;
    mLine := Context.LogicalLineNum - 1;
    if HasHits(mLine, Context) then
    begin
      DrawHits(mLine, Rect, Context);
    end;
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
    begin
      FHits := nil;
      TAtlasGuard.Report(TAtlasFeature.Search, E);
    end;
  end;
end;

end.
