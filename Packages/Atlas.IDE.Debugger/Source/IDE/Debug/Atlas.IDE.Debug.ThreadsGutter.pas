unit Atlas.IDE.Debug.ThreadsGutter;

// Threads im Quelltext (#852) als Schicht der Rinne (TAtlasIdeGutterMarks, #401): An jeder Zeile, an der andere
// Threads mit ihrem obersten eigenen Rahmen stehen, ein Zeichen mit der Anzahl; grau, wenn alle eingefroren sind.
// Tooltip: je Thread Kennung, Name, Wartepunkt, ⚑ und „eingefroren“; darunter je Thread ein Link, der zu ihm wechselt
// und auf seine Zeile springt. Abschaltbar über debug.threadsInSource; Sicherung über TAtlasFeature.Debugger.

interface

uses
  System.Types,
  Vcl.Graphics,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Editor.Elements,
  Atlas.IDE.Foundation.GutterMarks;

type
  TAtlasIdeDebugThreadsGutter = class(TAtlasGutterLayer)
  public const
    /// <summary>Höchstens so viele Links im Tooltip.</summary>
    cMaxLinks = 8;
  private
    /// <summary>Anzahl und Zustand der Marke aus dem letzten MarkAt; PaintIcon folgt unmittelbar.</summary>
    FCount: Integer;
    FAllFrozen: Boolean;
  public
    function Feature: TAtlasFeature; override;
    function Element: TAtlasDrawnElement; override;
    function Wanted: Boolean; override;
    procedure Track(const AFileName, AText: string; AOpened: Boolean); override;
    function HasMarks(const AFileName: string): Boolean; override;
    function MarkAt(const AFileName: string; ALine: Integer; const ALineText: string;
      AHasText: Boolean): Boolean; override;
    procedure PaintIcon(ACanvas: TCanvas; const AIcon: TRect; const AColors: TAtlasColors;
      ABack: TAtlasColor); override;
    function TipText(const AFileName: string; ALine: Integer; out ATitle, AText: string): Boolean; override;
    function TipLinks(const AFileName: string; ALine: Integer): TArray<string>; override;
    procedure OpenLink(const AFileName: string; ALine, AIndex: Integer); override;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Atlas.Core.Debug.ThreadMarks,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.ThreadFreeze,
  Atlas.IDE.Debug.ThreadsInSource,
  Atlas.UI.Debug.ThreadMarks;

const
  /// <summary>Zahlen ab hier zeigt das Zeichen als „9+“.</summary>
  cMaxShown = 9;
  /// <summary>Rundung der Ecken der Plakette.</summary>
  cCorner = 4;
  /// <summary>So viel kleiner als die Plakette ist die Schrift; nie kleiner als cMinFont.</summary>
  cFontInset = 3;
  cMinFont = 6;
  /// <summary>Anteil der Füllfarbe im Rand der Plakette.</summary>
  cBorderMix = 0.8;

/// <summary>Marke an ALine (0-basiert) von AFileName; -1 ohne.</summary>
function MarkIndex(const AFileName: string; ALine: Integer): Integer;
begin
  Result := TAtlasIdeDebugThreadsInSource.Marks.IndexAt(AFileName, ALine + 1);
end;

{ TAtlasIdeDebugThreadsGutter }

function TAtlasIdeDebugThreadsGutter.Feature: TAtlasFeature;
begin
  Result := TAtlasFeature.Debugger;
end;

function TAtlasIdeDebugThreadsGutter.Element: TAtlasDrawnElement;
begin
  Result := TAtlasDrawnElement.ThreadsInSource;
end;

function TAtlasIdeDebugThreadsGutter.Wanted: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DebugThreadsInSource and TAtlasIdeDebugThreadsInSource.Started;
end;

procedure TAtlasIdeDebugThreadsGutter.Track(const AFileName, AText: string; AOpened: Boolean);
begin
  // Die Marken kommen bei jedem Halt neu; Tippen ist im angehaltenen Programm selten.
end;

function TAtlasIdeDebugThreadsGutter.HasMarks(const AFileName: string): Boolean;
begin
  Result := TAtlasIdeDebugThreadsInSource.Marks.HasFile(AFileName);
end;

function TAtlasIdeDebugThreadsGutter.MarkAt(const AFileName: string; ALine: Integer; const ALineText: string;
  AHasText: Boolean): Boolean;
var
  mMarks: TAtlasDebugThreadMarks;
  mStacks: TArray<Integer>;
  mIndex, mThread: Integer;
begin
  mIndex := MarkIndex(AFileName, ALine);
  Result := mIndex >= 0;
  FCount := 0;
  FAllFrozen := False;
  if not Result then
  begin
    Exit;
  end;
  mMarks := TAtlasIdeDebugThreadsInSource.Marks;
  mStacks := mMarks.Marks[mIndex].Threads;
  FCount := Length(mStacks);
  FAllFrozen := True;
  for mThread in mStacks do
  begin
    if not TAtlasIdeDebugThreadFreeze.IsFrozen(TAtlasIdeDebugThreadsInSource.Stacks[mThread].ThreadId) then
    begin
      FAllFrozen := False;
      Break;
    end;
  end;
end;

procedure TAtlasIdeDebugThreadsGutter.PaintIcon(ACanvas: TCanvas; const AIcon: TRect; const AColors: TAtlasColors;
  ABack: TAtlasColor);
var
  mFill: TAtlasColor;
  mText: string;
  mOldFont: TFont;
  mSize: TSize;
begin
  // Plakette mit der Zahl der Threads, im Akzent; grau, wenn alle eingefroren sind.
  if FAllFrozen then
  begin
    mFill := AColors.Muted;
  end
  else
  begin
    mFill := AColors.Accent;
  end;
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := TColor(mFill);
  ACanvas.Pen.Color := TColor(TAtlasColorMath.Mix(mFill, ABack, cBorderMix));
  ACanvas.Pen.Width := 1;
  ACanvas.RoundRect(AIcon.Left, AIcon.Top, AIcon.Right, AIcon.Bottom, cCorner, cCorner);
  mText := IntToStr(Min(FCount, cMaxShown));
  if FCount > cMaxShown then
  begin
    mText := mText + '+';
  end;
  mOldFont := TFont.Create;
  try
    mOldFont.Assign(ACanvas.Font);
    ACanvas.Font.Height := -Max(cMinFont, AIcon.Height - cFontInset);
    ACanvas.Font.Style := [fsBold];
    ACanvas.Font.Color := TColor(ABack);
    ACanvas.Brush.Style := bsClear;
    mSize := ACanvas.TextExtent(mText);
    ACanvas.TextOut(AIcon.Left + (AIcon.Width - mSize.cx) div 2, AIcon.Top + (AIcon.Height - mSize.cy) div 2,
      mText);
  finally
    ACanvas.Font.Assign(mOldFont);
    mOldFont.Free;
  end;
end;

function TAtlasIdeDebugThreadsGutter.TipText(const AFileName: string; ALine: Integer;
  out ATitle, AText: string): Boolean;
var
  mIndex: Integer;
  mMarks: TAtlasDebugThreadMarks;
begin
  ATitle := '';
  AText := '';
  mIndex := MarkIndex(AFileName, ALine);
  Result := mIndex >= 0;
  if not Result then
  begin
    Exit;
  end;
  mMarks := TAtlasIdeDebugThreadsInSource.Marks;
  ATitle := TAtlasThreadMarkTexts.TipTitle(Length(mMarks.Marks[mIndex].Threads));
  AText := TAtlasThreadMarkTexts.TipText(TAtlasIdeDebugThreadsInSource.Stacks, mMarks.Marks[mIndex],
    TAtlasIdeDebugThreadsInSource.Flagged, TAtlasIdeDebugThreadFreeze.Frozen);
end;

function TAtlasIdeDebugThreadsGutter.TipLinks(const AFileName: string; ALine: Integer): TArray<string>;
var
  mIndex, mLink: Integer;
  mThreads: TArray<Integer>;
begin
  Result := nil;
  mIndex := MarkIndex(AFileName, ALine);
  if mIndex < 0 then
  begin
    Exit;
  end;
  mThreads := TAtlasIdeDebugThreadsInSource.Marks.Marks[mIndex].Threads;
  SetLength(Result, Min(Length(mThreads), cMaxLinks));
  for mLink := 0 to High(Result) do
  begin
    Result[mLink] := TAtlasThreadMarkTexts.SwitchLink(TAtlasIdeDebugThreadsInSource.Stacks[mThreads[mLink]]);
  end;
end;

procedure TAtlasIdeDebugThreadsGutter.OpenLink(const AFileName: string; ALine, AIndex: Integer);
var
  mIndex: Integer;
  mThreads: TArray<Integer>;
begin
  mIndex := MarkIndex(AFileName, ALine);
  if mIndex < 0 then
  begin
    Exit;
  end;
  mThreads := TAtlasIdeDebugThreadsInSource.Marks.Marks[mIndex].Threads;
  if (AIndex >= 0) and (AIndex <= High(mThreads)) then
  begin
    TAtlasIdeDebugThreadsInSource.Switch(mThreads[AIndex]);
  end;
end;

end.
