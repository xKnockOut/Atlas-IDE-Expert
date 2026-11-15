unit Atlas.Core.Editor.GutterPanel;

// Tafel und Klick der Atlas-Spalte in der Zeilenleiste (#768), ohne Open Tools API und VCL.
// - Ein Klick auf ◆ öffnet die Code-Aktionen der Zeile, auf ↑/↓ springt er bei einem Ziel gleich hin und listet
//   sonst die Ziele; auf ✕/▲/● zeigt er die Tafel samt Korrekturen des Servers.
// - Die Tafel eines Problems zeigt bei mehreren Meldungen in der Zeile den Code vor jeder.
// - Weist eine Methode in beide Richtungen (überschreibt und wird überschrieben), stehen Pfeile vor den Zielen.
// - Farbe des Symbols: Fehler, Warnung, Aktion und Pfeile fast deckend über dem Grund, Hinweise etwas blasser.

{$SCOPEDENUMS ON}

interface

uses
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Editor.GutterColumn;

type
  /// <summary>Was ein Klick auf das Symbol tut.</summary>
  TAtlasGutterClick = (
    /// <summary>Kein Symbol: nichts.</summary>
    None,
    /// <summary>Code-Aktionen der Zeile öffnen.</summary>
    OpenActions,
    /// <summary>Zum einzigen Ziel springen.</summary>
    GoToTarget,
    /// <summary>Tafel ohne Korrekturen (mehrere Ziele).</summary>
    ShowPanel,
    /// <summary>Tafel mit den Korrekturen des Servers (Problem).</summary>
    ShowPanelWithFixes);

  /// <summary>Welche Tafel zum Symbol gehört.</summary>
  TAtlasGutterPanelKind = (None, Problem, Action, Overrides);

  TAtlasGutterPanel = record
  public const
    /// <summary>Deckkraft der Symbole über dem Grund der Rinne; Hinweise blasser.</summary>
    cSymbolAlpha = 0.95;
    cHintAlpha = 0.9;
  public
    /// <summary>Klick auf ASymbol; ATargets: Zahl der Ziele bei ↑/↓.</summary>
    class function ClickOf(ASymbol: TAtlasGutterSymbol; ATargets: Integer): TAtlasGutterClick; static;
    /// <summary>Tafel zu ASymbol.</summary>
    class function PanelOf(ASymbol: TAtlasGutterSymbol): TAtlasGutterPanelKind; static;
    /// <summary>Zeilen der Tafel eines Problems: die Meldungen, bei mehreren mit ihrem Code davor.</summary>
    class function ProblemLines(const AProblems: TArray<TAtlasProblem>): TArray<string>; static;
    /// <summary>Gehört eine Code-Aktion als Korrektur in die Tafel? Nur Schnellkorrekturen, die gerade gehen.
    /// </summary>
    class function IsQuickFix(const AKind, ADisabled: string): Boolean; static;
    /// <summary>Pfeile vor den Zielen: nur, wenn die Methode in beide Richtungen weist.</summary>
    class function Arrows(const AEntry: TAtlasGutterOverrides; out AUp, ADown: string): Boolean; static;
    /// <summary>1-basierter Index des ersten Zeichens nach Leerzeichen und Tabs in ALine (hinter dem Ende bei
    /// leerer Zeile): dorthin setzt ein Klick auf ◆ den Cursor.</summary>
    class function CodeStart(const ALine: string): Integer; static;
    /// <summary>Farbe von ASymbol über dem Grund ABack.</summary>
    class function SymbolColor(ASymbol: TAtlasGutterSymbol; const AColors: TAtlasColors;
      ABack: TAtlasColor): TAtlasColor; static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasGutterPanel }

class function TAtlasGutterPanel.ClickOf(ASymbol: TAtlasGutterSymbol; ATargets: Integer): TAtlasGutterClick;
begin
  case ASymbol of
    TAtlasGutterSymbol.None:
      Result := TAtlasGutterClick.None;
    TAtlasGutterSymbol.Action:
      Result := TAtlasGutterClick.OpenActions;
    TAtlasGutterSymbol.Overrides, TAtlasGutterSymbol.Overridden:
      if ATargets = 1 then
      begin
        Result := TAtlasGutterClick.GoToTarget;
      end
      else
      begin
        Result := TAtlasGutterClick.ShowPanel;
      end;
  else
    Result := TAtlasGutterClick.ShowPanelWithFixes;
  end;
end;

class function TAtlasGutterPanel.PanelOf(ASymbol: TAtlasGutterSymbol): TAtlasGutterPanelKind;
begin
  case ASymbol of
    TAtlasGutterSymbol.Error, TAtlasGutterSymbol.Warning, TAtlasGutterSymbol.Hint:
      Result := TAtlasGutterPanelKind.Problem;
    TAtlasGutterSymbol.Action:
      Result := TAtlasGutterPanelKind.Action;
    TAtlasGutterSymbol.Overrides, TAtlasGutterSymbol.Overridden:
      Result := TAtlasGutterPanelKind.Overrides;
  else
    Result := TAtlasGutterPanelKind.None;
  end;
end;

class function TAtlasGutterPanel.ProblemLines(const AProblems: TArray<TAtlasProblem>): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, Length(AProblems));
  for mIndex := 0 to High(AProblems) do
  begin
    if (AProblems[mIndex].Code <> '') and (Length(AProblems) > 1) then
    begin
      Result[mIndex] := AProblems[mIndex].Code + ': ' + AProblems[mIndex].Message;
    end
    else
    begin
      Result[mIndex] := AProblems[mIndex].Message;
    end;
  end;
end;

class function TAtlasGutterPanel.IsQuickFix(const AKind, ADisabled: string): Boolean;
begin
  Result := (ADisabled = '') and AKind.StartsWith('quickfix');
end;

class function TAtlasGutterPanel.Arrows(const AEntry: TAtlasGutterOverrides; out AUp, ADown: string): Boolean;
begin
  Result := (Length(AEntry.Overrides) > 0) and (Length(AEntry.Overridden) > 0);
  AUp := '';
  ADown := '';
  if Result then
  begin
    AUp := '↑ ';
    ADown := '↓ ';
  end;
end;

class function TAtlasGutterPanel.CodeStart(const ALine: string): Integer;
begin
  Result := 1;
  while (Result <= Length(ALine)) and CharInSet(ALine[Result], [' ', #9]) do
  begin
    Inc(Result);
  end;
end;

class function TAtlasGutterPanel.SymbolColor(ASymbol: TAtlasGutterSymbol; const AColors: TAtlasColors;
  ABack: TAtlasColor): TAtlasColor;
begin
  case ASymbol of
    TAtlasGutterSymbol.Error:
      Result := TAtlasColorMath.Mix(AColors.Error, ABack, cSymbolAlpha);
    TAtlasGutterSymbol.Warning:
      Result := TAtlasColorMath.Mix(AColors.Warn, ABack, cSymbolAlpha);
    TAtlasGutterSymbol.Hint:
      Result := TAtlasColorMath.Mix(AColors.Muted, ABack, cHintAlpha);
    TAtlasGutterSymbol.Action:
      Result := TAtlasColorMath.Mix(AColors.Accent, ABack, cSymbolAlpha);
  else
    Result := TAtlasColorMath.Mix(AColors.Add, ABack, cSymbolAlpha);
  end;
end;

end.
