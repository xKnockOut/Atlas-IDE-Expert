unit Atlas.Core.Debug.RunToColumnFlow;

// Entscheidungen der Spalte „Bis hier ausführen“ in der Rinne (#851) außerhalb der Codezeilen, ohne IDE prüfbar
// (#1967): wann die Spalte neu angefordert und der Text neu gelesen wird, ob die Maus noch auf derselben Zeile steht,
// wann der Tooltip erscheint und wo das ▶ liegt. Atlas.IDE.Debug.RunToColumn zeichnet und fragt Editor und Debugger.

interface

uses
  System.Types;

type
  /// <summary>Zeile der Rinne: Datei, Zeile (0-basiert), Zelle und oberste sichtbare Zeile beim Zeichnen.</summary>
  TAtlasRunToRow = record
    FileName: string;
    /// <summary>0-basiert.</summary>
    Line: Integer;
    Rect: TRect;
    TopRow: Integer;
  end;

  TAtlasRunToColumnFlow = class
  public
    /// <summary>Spalte neu anfordern: keine (AColumn &lt; 0) oder andere Breite.</summary>
    class function NeedsColumn(AColumn, AWidth, AWanted: Integer): Boolean; static;
    /// <summary>Text neu lesen: andere Datei oder AInterval ms seit dem letzten Lesen.</summary>
    class function ReadDue(ASameFile: Boolean; ANow, AReadAt, AInterval: UInt64): Boolean; static;
    /// <summary>Steht ARow noch dort, wo sie gezeichnet wurde: gleiche Datei, nicht gescrollt?</summary>
    class function StillThere(const ARow: TAtlasRunToRow; const AFileName: string; ATopRow: Integer): Boolean;
      static;
    /// <summary>Gleiche Zeile wie die, über der die Maus steht (AHovering, AHover)?</summary>
    class function SameHover(AHovering: Boolean; const AHover, ARow: TAtlasRunToRow): Boolean; static;
    /// <summary>Tooltip zeigen: noch nicht gezeigt und mindestens ADelay ms über der Zeile.</summary>
    class function TipDue(AShown: Boolean; ANow, ASince, ADelay: UInt64): Boolean; static;
    /// <summary>Ecken des ▶ in ARect: Kantenlänge mindestens AMin, sonst Zelle weniger APad, mittig.</summary>
    class function Arrow(const ARect: TRect; AMin, APad: Integer): TArray<TPoint>; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math;

{ TAtlasRunToColumnFlow }

class function TAtlasRunToColumnFlow.NeedsColumn(AColumn, AWidth, AWanted: Integer): Boolean;
begin
  Result := (AColumn < 0) or (AWidth <> AWanted);
end;

class function TAtlasRunToColumnFlow.ReadDue(ASameFile: Boolean; ANow, AReadAt, AInterval: UInt64): Boolean;
begin
  Result := not ASameFile or (ANow - AReadAt >= AInterval);
end;

class function TAtlasRunToColumnFlow.StillThere(const ARow: TAtlasRunToRow; const AFileName: string;
  ATopRow: Integer): Boolean;
begin
  Result := SameText(ARow.FileName, AFileName) and (ARow.TopRow = ATopRow);
end;

class function TAtlasRunToColumnFlow.SameHover(AHovering: Boolean; const AHover, ARow: TAtlasRunToRow): Boolean;
begin
  Result := AHovering and SameText(AHover.FileName, ARow.FileName) and (AHover.Line = ARow.Line);
end;

class function TAtlasRunToColumnFlow.TipDue(AShown: Boolean; ANow, ASince, ADelay: UInt64): Boolean;
begin
  Result := not AShown and (ANow - ASince >= ADelay);
end;

class function TAtlasRunToColumnFlow.Arrow(const ARect: TRect; AMin, APad: Integer): TArray<TPoint>;
var
  mSize, mLeft, mTop: Integer;
begin
  mSize := Max(AMin, Min(ARect.Width, ARect.Height) - APad);
  mLeft := ARect.Left + (ARect.Width - mSize) div 2;
  mTop := ARect.Top + (ARect.Height - mSize) div 2;
  Result := [Point(mLeft, mTop), Point(mLeft + mSize - 1, mTop + mSize div 2), Point(mLeft, mTop + mSize - 1)];
end;

end.
