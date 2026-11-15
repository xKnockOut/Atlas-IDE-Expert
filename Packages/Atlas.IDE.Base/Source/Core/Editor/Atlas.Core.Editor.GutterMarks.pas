unit Atlas.Core.Editor.GutterMarks;

// Entscheidungen der gemeinsamen Zeichenschicht der Rinne (#401, #1967), ohne VCL und Open Tools API.
// Atlas.IDE.Foundation.GutterMarks liest den oberen Editor und zeichnet; hier fällt:
// - TAtlasGutterTracker: wann die Schichten die Datei vorn neu verankern. Eine neue Datei sofort (AOpened), eine
//   Änderung erst nach einer Tipp-Pause von cQuietMs, und nur einmal je Stand des Textes.
// - TAtlasGutterClickLine: Rechtsklick in die Rinne gilt für die Befehle des Kontextmenüs, höchstens cLineMs lang
//   und nur für dieselbe Datei; ein Befehl verbraucht ihn.
// - TAtlasGutterLayout.IconRect: Lage der Symbole in einer Rinnenzeile.
// Zeiten in Millisekunden eines fortlaufenden Zählers; der Aufrufer nennt die aktuelle Zeit (ANow).

interface

uses
  System.Types;

type
  {$SCOPEDENUMS ON}
  /// <summary>Was die Rinne nach einem Blick auf den oberen Editor tut.</summary>
  TAtlasGutterTrackAction = (
    /// <summary>Nichts (gleicher Stand oder Tipp-Pause läuft noch).</summary>
    None,
    /// <summary>Andere Datei vorn: Schichten sofort zuordnen (AOpened), Zeilen und Tooltip vergessen.</summary>
    NewFile,
    /// <summary>Nach der Tipp-Pause neu verankern.</summary>
    Retrack);
  {$SCOPEDENUMS OFF}

  TAtlasGutterTracker = record
  public const
    /// <summary>Tipp-Pause, nach der die Schichten neu verankern.</summary>
    cQuietMs = 300;
  private
    FFileName: string;
    FText: string;
    FTrackedText: string;
    FChangedAt: UInt64;
  public
    /// <summary>Datei vorn vergessen: Der nächste Blick zählt als neue Datei (neue Schicht, wieder eingeschaltet).
    /// </summary>
    procedure Reset;
    /// <summary>Der obere Editor zeigt AFileName mit AText.</summary>
    function Step(const AFileName, AText: string; ANow: UInt64): TAtlasGutterTrackAction;
    /// <summary>Datei des letzten Blicks; '' nach Reset.</summary>
    function FileName: string;
    /// <summary>Text des letzten Blicks.</summary>
    function Text: string;
  end;

  TAtlasGutterClickLine = record
  public const
    /// <summary>So lange gilt ein Rechtsklick in die Rinne für die Befehle.</summary>
    cLineMs = 60000;
  private
    FFileName: string;
    FLine: Integer;
    FAt: UInt64;
  public
    /// <summary>Rechtsklick an ALine (0-basiert) von AFileName.</summary>
    procedure Remember(const AFileName: string; ALine: Integer; ANow: UInt64);
    procedure Forget;
    /// <summary>Zeile des letzten Rechtsklicks, wenn er zu AFileName gehört (Schreibweise des Pfads egal) und
    /// höchstens cLineMs alt ist; vergisst ihn in jedem Fall.</summary>
    function Take(const AFileName: string; ANow: UInt64; out ALine: Integer): Boolean;
  end;

  TAtlasGutterLayout = class
  public
    /// <summary>Rechteck des Symbols Nummer ASlot (0 = ganz links, negativ wie 0) in einer Rinnenzeile AGutter:
    /// senkrecht mittig, Höhe nach Zeile (6 bis 14 Punkte), Breite vier Fünftel davon, 2 Punkte Abstand.</summary>
    class function IconRect(const AGutter: TRect; ASlot: Integer): TRect; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Atlas.Core.Projects.Summary;

{ TAtlasGutterTracker }

procedure TAtlasGutterTracker.Reset;
begin
  FFileName := '';
end;

function TAtlasGutterTracker.Step(const AFileName, AText: string; ANow: UInt64): TAtlasGutterTrackAction;
begin
  Result := TAtlasGutterTrackAction.None;
  if not SameText(FFileName, AFileName) then
  begin
    FFileName := AFileName;
    FText := AText;
    FTrackedText := AText;
    Result := TAtlasGutterTrackAction.NewFile;
  end
  else if FText <> AText then
  begin
    FText := AText;
    FChangedAt := ANow;
  end
  else if (FTrackedText <> FText) and (ANow - FChangedAt >= cQuietMs) then
  begin
    FTrackedText := FText;
    Result := TAtlasGutterTrackAction.Retrack;
  end;
end;

function TAtlasGutterTracker.FileName: string;
begin
  Result := FFileName;
end;

function TAtlasGutterTracker.Text: string;
begin
  Result := FText;
end;

{ TAtlasGutterClickLine }

procedure TAtlasGutterClickLine.Remember(const AFileName: string; ALine: Integer; ANow: UInt64);
begin
  FFileName := AFileName;
  FLine := ALine;
  FAt := ANow;
end;

procedure TAtlasGutterClickLine.Forget;
begin
  FFileName := '';
  FLine := -1;
end;

function TAtlasGutterClickLine.Take(const AFileName: string; ANow: UInt64; out ALine: Integer): Boolean;
begin
  ALine := FLine;
  Result := (FFileName <> '') and (FLine >= 0) and
    (TAtlasProjectSummaries.NormalizedPath(FFileName) = TAtlasProjectSummaries.NormalizedPath(AFileName)) and
    (ANow - FAt <= cLineMs);
  if not Result then
  begin
    ALine := -1;
  end;
  Forget;
end;

{ TAtlasGutterLayout }

class function TAtlasGutterLayout.IconRect(const AGutter: TRect; ASlot: Integer): TRect;
var
  mHeight, mWidth, mTop, mLeft: Integer;
begin
  mHeight := Max(6, Min(AGutter.Height - 4, 14));
  mWidth := Max(5, (mHeight * 4) div 5);
  mTop := AGutter.Top + (AGutter.Height - mHeight) div 2;
  mLeft := AGutter.Left + 2 + Max(0, ASlot) * (mWidth + 2);
  Result := TRect.Create(mLeft, mTop, mLeft + mWidth, mTop + mHeight);
end;

end.
