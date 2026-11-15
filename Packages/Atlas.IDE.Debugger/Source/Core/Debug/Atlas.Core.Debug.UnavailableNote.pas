unit Atlas.Core.Debug.UnavailableNote;

// Entscheidungen von „kein Zugriff auf Wert“ (#840) rund um den Hinweis, ohne IDE prüfbar (#1967): ob ein Wert
// erklärt wird, ob Atlas dafür den Server fragt, welche Projektoption und welcher Ursprung zur Ursache gehören,
// welche Korrektur ein Klick meint und ob sie zur letzten Erklärung passt. Atlas.IDE.Debug.Unavailable fragt
// Debugger, Editor und Server und schreibt die Texte.

interface

uses
  Atlas.Core.Hover.DebugValue,
  Atlas.Core.Debug.Unavailable;

{$SCOPEDENUMS ON}

type
  /// <summary>Woher ein Schalter kommt, für den Hinweis: unbekannt, Direktive mit Datei, Projektoption,
  /// Voreinstellung.</summary>
  TAtlasUnavailableOrigin = (None, Directive, Project, Default);

  TAtlasUnavailableNote = class
  public const
    cDebugInfoOption = 'DCC_DebugInformation';
    cLocalSymbolsOption = 'DCC_LocalDebugSymbols';
    cOptimizeOption = 'DCC_Optimize';
    cDebugDcusOption = 'DCC_DebugDCUs';
  public
    /// <summary>Wert erklären: Auswertung gescheitert mit einem bekannten Text (APatterns: eigene Texte).</summary>
    class function CanExplain(const AValue: TAtlasDebugValue; const APatterns: TArray<string>): Boolean; static;
    /// <summary>Server fragen: Sitzung, Editor der Datei des Halts und Name da; sonst nur mit dem Bekannten.
    /// </summary>
    class function AskServer(AHasSession, AHasBuffer: Boolean; const AName: string): Boolean; static;
    /// <summary>Projektoption der Ursache für den Ursprung; '' ohne.</summary>
    class function OptionOf(ACause: TAtlasUnavailableCause): string; static;
    /// <summary>Ursache mit Lage zur Verwendung der Variablen („noch nicht“, „nicht mehr“).</summary>
    class function WithLifetime(ACause: TAtlasUnavailableCause): Boolean; static;
    class function OriginOf(const ASwitch: TAtlasUnavailableSwitch): TAtlasUnavailableOrigin; static;
    /// <summary>Zwei Sätze mit Leerzeichen; ohne zweiten nur der erste.</summary>
    class function Joined(const AFirst, ASecond: string): string; static;
    /// <summary>Korrektur zum Knopf AIndex des Hinweises; False ohne Knopf oder mit fremder Kennung.</summary>
    class function FixOf(const AValue: TAtlasDebugValue; AIndex: Integer; out AFix: TAtlasUnavailableFix): Boolean;
      static;
    /// <summary>Korrektur gehört zur letzten Erklärung (derselbe Ausdruck, sie bietet AFix an).</summary>
    class function FixAllowed(const AExpression, ALastExpression: string;
      const AExplanation: TAtlasUnavailableExplanation; AFix: TAtlasUnavailableFix): Boolean; static;
  end;

implementation

{ TAtlasUnavailableNote }

class function TAtlasUnavailableNote.CanExplain(const AValue: TAtlasDebugValue;
  const APatterns: TArray<string>): Boolean;
begin
  Result := (AValue.State = TAtlasDebugValueState.Failed) and TAtlasDebugUnavailable.IsUnavailable(AValue.Text,
    APatterns);
end;

class function TAtlasUnavailableNote.AskServer(AHasSession, AHasBuffer: Boolean; const AName: string): Boolean;
begin
  Result := AHasSession and AHasBuffer and (AName <> '');
end;

class function TAtlasUnavailableNote.OptionOf(ACause: TAtlasUnavailableCause): string;
begin
  case ACause of
    TAtlasUnavailableCause.NoDebugInfo:
      Result := cDebugInfoOption;
    TAtlasUnavailableCause.NoLocalSymbols:
      Result := cLocalSymbolsOption;
    TAtlasUnavailableCause.Optimization:
      Result := cOptimizeOption;
  else
    Result := '';
  end;
end;

class function TAtlasUnavailableNote.WithLifetime(ACause: TAtlasUnavailableCause): Boolean;
begin
  Result := ACause in [TAtlasUnavailableCause.Optimization, TAtlasUnavailableCause.Lifetime];
end;

class function TAtlasUnavailableNote.OriginOf(const ASwitch: TAtlasUnavailableSwitch): TAtlasUnavailableOrigin;
begin
  if not ASwitch.Known then
  begin
    Exit(TAtlasUnavailableOrigin.None);
  end;
  case ASwitch.Source of
    TAtlasSwitchSource.Directive, TAtlasSwitchSource.Include:
      if ASwitch.FileName <> '' then
      begin
        Result := TAtlasUnavailableOrigin.Directive;
      end
      else
      begin
        Result := TAtlasUnavailableOrigin.None;
      end;
    TAtlasSwitchSource.Project:
      Result := TAtlasUnavailableOrigin.Project;
  else
    Result := TAtlasUnavailableOrigin.Default;
  end;
end;

class function TAtlasUnavailableNote.Joined(const AFirst, ASecond: string): string;
begin
  Result := AFirst;
  if ASecond <> '' then
  begin
    Result := Result + ' ' + ASecond;
  end;
end;

class function TAtlasUnavailableNote.FixOf(const AValue: TAtlasDebugValue; AIndex: Integer;
  out AFix: TAtlasUnavailableFix): Boolean;
var
  mId: Integer;
begin
  AFix := Low(TAtlasUnavailableFix);
  Result := (AIndex >= 0) and (AIndex <= High(AValue.Note.Fixes));
  if not Result then
  begin
    Exit;
  end;
  mId := AValue.Note.Fixes[AIndex].Id;
  Result := (mId >= Ord(Low(TAtlasUnavailableFix))) and (mId <= Ord(High(TAtlasUnavailableFix)));
  if Result then
  begin
    AFix := TAtlasUnavailableFix(mId);
  end;
end;

class function TAtlasUnavailableNote.FixAllowed(const AExpression, ALastExpression: string;
  const AExplanation: TAtlasUnavailableExplanation; AFix: TAtlasUnavailableFix): Boolean;
begin
  Result := (AExpression = ALastExpression) and AExplanation.HasFix(AFix);
end;

end.
