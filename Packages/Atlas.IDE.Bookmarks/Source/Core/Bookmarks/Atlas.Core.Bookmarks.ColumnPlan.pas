unit Atlas.Core.Bookmarks.ColumnPlan;

// Entscheidungen der Spalte der schnellen Lesezeichen (#1104), ohne VCL und
// Open Tools API. Atlas.IDE.Bookmarks.QuickColumn zeichnet, nimmt Klicks und
// fragt den Editor; was es dabei entscheidet, steht hier:
// - TAtlasQuickTrack: Datei und Text im oberen Editor. Neue Datei: gleich
//   wiederfinden; geänderter Text: warten; nach der Tipp-Pause einmal
//   wiederfinden.
// - Ob die Marker einer Zeile noch gelten (Zeilentext passt zum Anker),
//   ob zwei Zeilen dieselbe sind (Überfahren), welche Stufe der Rinne die
//   Zeilennummern zeichnet, die Farbe der Ziffer auf dem Marker.
// - Zeitpunkte: Tooltip nach dem Überfahren, Protokoll „nie gezeichnet“,
//   Klick über das Mausereignis des Editors, wenn OnMessage ihn eben schon
//   genommen hat.

{$SCOPEDENUMS ON}

interface

uses
  Atlas.Core.Style.Color;

type
  /// <summary>Was der Zeitgeber nach einem Blick auf den oberen Editor tut.</summary>
  TAtlasQuickTrackStep = (
    /// <summary>Nichts (kein Editor, Pause läuft oder schon erledigt).</summary>
    Idle,
    /// <summary>Neue Datei vorn: gleich wiederfinden.</summary>
    NewFile,
    /// <summary>Text geändert: Pause abwarten.</summary>
    Changed,
    /// <summary>Pause vorbei: jetzt wiederfinden.</summary>
    Settled);

  /// <summary>Datei und Text im oberen Editor mit Tipp-Pause.</summary>
  TAtlasQuickTrack = record
  public
    FileName: string;
    Text: string;
    ChangedAt: UInt64;
    Done: Boolean;
    /// <summary>Oberer Editor zeigt AFileName mit AText ('' = kein Editor); merkt den Stand und sagt, was zu tun
    /// ist. AQuietMs ist die Tipp-Pause.</summary>
    function Step(const AFileName, AText: string; ANowMs, AQuietMs: UInt64): TAtlasQuickTrackStep;
    /// <summary>Spalte aus: alles vergessen.</summary>
    procedure Reset;
  end;

  TAtlasQuickColumnPlan = record
  public
    /// <summary>Gelten die Marker noch? Nur, wenn der Text der Zeile (AHasText) zum Anker AAnchorText passt;
    /// ohne Text gilt der Marker.</summary>
    class function KeepsMarks(AHasText: Boolean; const ALineText, AAnchorText: string): Boolean; static;
    /// <summary>Gleiche Zeile: dasselbe Editorfenster, dieselbe Zeile, dieselbe Datei (Groß/klein egal).</summary>
    class function SameRow(AWndA: NativeUInt; ALineA: Integer; const AFileA: string; AWndB: NativeUInt;
      ALineB: Integer; const AFileB: string): Boolean; static;
    /// <summary>Zeichnet die Stufe die Zeilennummern? Nicht die erste Stufe (AFirstStage), und ihr Rechteck
    /// (ALeft, AWidth) grenzt rechts an die Spalte (AColumnRight).</summary>
    class function IsLineNumberStage(AFirstStage: Boolean; ALeft, AWidth, AColumnRight: Integer): Boolean; static;
    /// <summary>Ziffer auf dem Marker: Schwarz oder Weiß, je nachdem, was sich stärker von AFill abhebt.</summary>
    class function DigitColor(AFill: TAtlasColor): TAtlasColor; static;
    /// <summary>Tooltip zeigen: noch nicht sichtbar und AHoverMs seit Beginn des Überfahrens.</summary>
    class function TipDue(ATipShown: Boolean; ASince, ANowMs, AHoverMs: UInt64): Boolean; static;
    /// <summary>Protokoll „Spalte nie gezeichnet“: Spalte angefordert (AColumn >= 0), noch nicht gemeldet, eine
    /// Datei vorn und AWaitMs seit der Anforderung.</summary>
    class function ReportNotPainted(AColumn: Integer; AReported: Boolean; const AFileName: string;
      ARequestedAt, ANowMs, AWaitMs: UInt64): Boolean; static;
    /// <summary>Hat OnMessage den Klick eben schon genommen (innerhalb von cTakenMs)?</summary>
    class function RecentlyTaken(AClickedAt, ANowMs: UInt64): Boolean; static;
  public const
    cTakenMs = 500;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Editor.LineAnchor;

{ TAtlasQuickTrack }

function TAtlasQuickTrack.Step(const AFileName, AText: string; ANowMs, AQuietMs: UInt64): TAtlasQuickTrackStep;
begin
  Result := TAtlasQuickTrackStep.Idle;
  if AFileName = '' then
  begin
    Exit;
  end;
  if not SameText(FileName, AFileName) then
  begin
    FileName := AFileName;
    Text := AText;
    Done := True;
    Exit(TAtlasQuickTrackStep.NewFile);
  end;
  if Text <> AText then
  begin
    Text := AText;
    ChangedAt := ANowMs;
    Done := False;
    Exit(TAtlasQuickTrackStep.Changed);
  end;
  if Done or (ANowMs - ChangedAt < AQuietMs) then
  begin
    Exit;
  end;
  Done := True;
  Result := TAtlasQuickTrackStep.Settled;
end;

procedure TAtlasQuickTrack.Reset;
begin
  FileName := '';
  Text := '';
end;

{ TAtlasQuickColumnPlan }

class function TAtlasQuickColumnPlan.KeepsMarks(AHasText: Boolean; const ALineText, AAnchorText: string): Boolean;
begin
  Result := not AHasText or (TAtlasLineAnchors.Normalize(ALineText) = AAnchorText);
end;

class function TAtlasQuickColumnPlan.SameRow(AWndA: NativeUInt; ALineA: Integer; const AFileA: string;
  AWndB: NativeUInt; ALineB: Integer; const AFileB: string): Boolean;
begin
  Result := (AWndA = AWndB) and (ALineA = ALineB) and SameText(AFileA, AFileB);
end;

class function TAtlasQuickColumnPlan.IsLineNumberStage(AFirstStage: Boolean; ALeft, AWidth,
  AColumnRight: Integer): Boolean;
begin
  Result := not AFirstStage and (ALeft >= AColumnRight - 1) and (ALeft <= AColumnRight + 2) and (AWidth > 0);
end;

class function TAtlasQuickColumnPlan.DigitColor(AFill: TAtlasColor): TAtlasColor;
const
  cBlack = TAtlasColor($000000);
  cWhite = TAtlasColor($FFFFFF);
begin
  Result := cBlack;
  if TAtlasColorMath.Contrast(cWhite, AFill) > TAtlasColorMath.Contrast(cBlack, AFill) then
  begin
    Result := cWhite;
  end;
end;

class function TAtlasQuickColumnPlan.TipDue(ATipShown: Boolean; ASince, ANowMs, AHoverMs: UInt64): Boolean;
begin
  Result := not ATipShown and (ANowMs - ASince >= AHoverMs);
end;

class function TAtlasQuickColumnPlan.ReportNotPainted(AColumn: Integer; AReported: Boolean; const AFileName: string;
  ARequestedAt, ANowMs, AWaitMs: UInt64): Boolean;
begin
  Result := (AColumn >= 0) and not AReported and (AFileName <> '') and (ANowMs - ARequestedAt >= AWaitMs);
end;

class function TAtlasQuickColumnPlan.RecentlyTaken(AClickedAt, ANowMs: UInt64): Boolean;
begin
  Result := ANowMs - AClickedAt < cTakenMs;
end;

end.
