unit Atlas.IDE.VersionControl.LineChangesPaint;

// Hilfen der Änderungsmarken (#507) im Editor ohne eigenen Zustand: Balken
// und Dreieck in der Rinne, Spalte hinter dem Zeilenende, alter Stand einer
// Änderung für das Fenster, Neuzeichnen des oberen Editors und Sprung zur
// Zeile einer Änderung. Nur im Hauptthread.

interface

uses
  Winapi.Windows,
  System.Types,
  Atlas.Core.Style.Color,
  Atlas.Core.Editor.LineChanges;

type
  TAtlasLineChangesPaint = class
  public const
    /// <summary>Höchstens so viele alte Zeilen im Fenster.</summary>
    cMaxOldLines = 15;
  public
    /// <summary>Balken ABar in der Farbe AColor.</summary>
    class procedure FillBar(ADC: HDC; const ABar: TRect; AColor: TAtlasColor); static;
    /// <summary>Dreieck nach rechts an ALeft: über der Zeile ARect, mit AAtEnd (Dateiende) unter ihr.</summary>
    class procedure PaintDeleted(ADC: HDC; ALeft, ASize: Integer; const ARect: TRect; AAtEnd: Boolean;
      AColor: TAtlasColor); static;
    /// <summary>Editorspalte (1-basiert) hinter dem letzten Zeichen von ALine; Tabs aufgelöst.</summary>
    class function EndColumn(const ALine: string; ATabWidth: Integer): Integer; static;
    /// <summary>Alter Stand einer Änderung, höchstens cMaxOldLines Zeilen; leere Zeilen bleiben sichtbar.</summary>
    class function OldText(const AChange: TAtlasLineChange): string; static;
    /// <summary>Den oberen Editor neu zeichnen.</summary>
    class procedure Invalidate; static;
    /// <summary>Cursor in AFileName auf die Zeile ALine (0-basiert), begrenzt auf ALineCount Zeilen.</summary>
    class procedure GoToLine(const AFileName: string; ALine, ALineCount: Integer); static;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Vcl.Graphics,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Editor.Pairs,
  Atlas.UI.Strings,
  Atlas.UI.VersionControl.Strings,
  Atlas.IDE.Foundation.EditorRefresh,
  Atlas.IDE.Foundation.Navigation;

class function TAtlasLineChangesPaint.OldText(const AChange: TAtlasLineChange): string;
var
  mIndex, mShown: Integer;
begin
  if AChange.Kind = TAtlasLineChangeKind.Added then
  begin
    Exit(TAtlasStrings.Text(TAtlasTextId.ChangeAddedTitle));
  end;
  mShown := Min(Length(AChange.OldLines), cMaxOldLines);
  Result := '';
  for mIndex := 0 to mShown - 1 do
  begin
    if mIndex > 0 then
    begin
      Result := Result + sLineBreak;
    end;
    Result := Result + AChange.OldLines[mIndex];
    if AChange.OldLines[mIndex] = '' then
    begin
      Result := Result + ' ';
    end;
  end;
  if Length(AChange.OldLines) > mShown then
  begin
    Result := Result + sLineBreak + TAtlasVcsStrings.Fmt(TAtlasVcsTextId.ChangeMoreLines,
      [Length(AChange.OldLines) - mShown]);
  end;
end;

class procedure TAtlasLineChangesPaint.FillBar(ADC: HDC; const ABar: TRect; AColor: TAtlasColor);
var
  mBrush: HGDIOBJ;
begin
  mBrush := CreateSolidBrush(ColorToRGB(TColor(AColor)));
  try
    FillRect(ADC, ABar, mBrush);
  finally
    DeleteObject(mBrush);
  end;
end;

class procedure TAtlasLineChangesPaint.PaintDeleted(ADC: HDC; ALeft, ASize: Integer; const ARect: TRect;
  AAtEnd: Boolean; AColor: TAtlasColor);
var
  mPoints: array[0..2] of TPoint;
  mBrush, mPen, mOldBrush, mOldPen: HGDIOBJ;
begin
  if AAtEnd then
  begin
    mPoints[0] := Point(ALeft, ARect.Bottom - 2 * ASize);
    mPoints[1] := Point(ALeft, ARect.Bottom);
    mPoints[2] := Point(ALeft + ASize, ARect.Bottom - ASize);
  end
  else
  begin
    mPoints[0] := Point(ALeft, ARect.Top);
    mPoints[1] := Point(ALeft, ARect.Top + 2 * ASize);
    mPoints[2] := Point(ALeft + ASize, ARect.Top + ASize);
  end;
  mBrush := CreateSolidBrush(ColorToRGB(TColor(AColor)));
  mPen := CreatePen(PS_SOLID, 1, ColorToRGB(TColor(AColor)));
  mOldBrush := SelectObject(ADC, mBrush);
  mOldPen := SelectObject(ADC, mPen);
  try
    Polygon(ADC, mPoints, Length(mPoints));
  finally
    SelectObject(ADC, mOldPen);
    SelectObject(ADC, mOldBrush);
    DeleteObject(mPen);
    DeleteObject(mBrush);
  end;
end;

class function TAtlasLineChangesPaint.EndColumn(const ALine: string; ATabWidth: Integer): Integer;
begin
  Result := Length(TAtlasPairs.DisplayLine(TrimRight(ALine), ATabWidth)) + 1;
end;

class procedure TAtlasLineChangesPaint.Invalidate;
var
  mServices: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    TAtlasIdeEditorRefresh.InvalidateTop(mServices);
  end;
end;

class procedure TAtlasLineChangesPaint.GoToLine(const AFileName: string; ALine, ALineCount: Integer);
begin
  TAtlasIdeNavigation.GoToLocation(AFileName, Min(ALine, Max(0, ALineCount - 1)), 0);
end;

end.
