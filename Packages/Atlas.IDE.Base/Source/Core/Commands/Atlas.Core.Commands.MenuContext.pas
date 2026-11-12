unit Atlas.Core.Commands.MenuContext;

// Lage beim Öffnen des Kontextmenüs im Editor (TAtlasMenuContext) und die
// Regeln, nach denen das Untermenü „Atlas“ daraus nur passende Einträge zeigt:
// Debuggen nur während einer Debug-Sitzung, Tests nur in einer DUnitX-
// Testunit, „Im Designer zeigen“ nur mit Formular, Regionen nur, wenn die Unit
// welche hat, die Zahl der Befunde am Untermenü „Befunde“. Dazu Trennlinien
// nur zwischen sichtbaren Einträgen, weil ausgeblendete Einträge sonst doppelte
// Linien hinterlassen.
// Ohne VCL und Open Tools API; die IDE-Seite liest die Lage in
// Atlas.IDE.Commands.MenuContext.

interface

uses
  Atlas.Core.Modules.Contract;

type
  TAtlasMenuContextRules = record
  public
    /// <summary>Ist AText eine DUnitX-Testunit (uses DUnitX.TestFramework oder [TestFixture])?</summary>
    class function IsTestUnit(const AText: string): Boolean; static;
    /// <summary>Enthält AText eine Region ({$REGION …})?</summary>
    class function HasRegions(const AText: string): Boolean; static;
    /// <summary>Lage aus Dateiname, Text und den Angaben der IDE.</summary>
    class function Read(const AFileName, AText: string; AHasForm, ADebugging: Boolean;
      AProblemCount: Integer): TAtlasMenuContext; static;
    /// <summary>Zeigen? Ohne bekannte Lage (AKnown False), mit abgeschalteter Einstellung (AContextual False) oder
    /// ohne Bedingung immer, sonst nach AWhen.</summary>
    class function Applies(AKnown, AContextual: Boolean; const AWhen: TAtlasMenuWhen;
      const AContext: TAtlasMenuContext): Boolean; static;
    /// <summary>Name eines Untermenüs mit Zahl, etwa „Befunde (3)“; ACount 0 = nur der Name.</summary>
    class function CountedCaption(const ACaption: string; ACount: Integer): string; static;
    /// <summary>Sichtbarkeit einer Liste von Einträgen (AIsLine = Trennlinie): Befehle behalten AVisible, eine
    /// Trennlinie erscheint nur zwischen zwei sichtbaren Befehlen und nie doppelt.</summary>
    class function Separators(const AIsLine, AVisible: TArray<Boolean>): TArray<Boolean>; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils;

class function TAtlasMenuContextRules.IsTestUnit(const AText: string): Boolean;
begin
  Result := ContainsText(AText, 'DUnitX.TestFramework') or ContainsText(AText, '[TestFixture');
end;

class function TAtlasMenuContextRules.HasRegions(const AText: string): Boolean;
begin
  Result := ContainsText(AText, '{$REGION');
end;

class function TAtlasMenuContextRules.Read(const AFileName, AText: string; AHasForm, ADebugging: Boolean;
  AProblemCount: Integer): TAtlasMenuContext;
begin
  Result := Default(TAtlasMenuContext);
  Result.FileName := AFileName;
  Result.TestUnit := IsTestUnit(AText);
  Result.HasRegions := HasRegions(AText);
  Result.HasForm := AHasForm;
  Result.Debugging := ADebugging;
  Result.ProblemCount := AProblemCount;
end;

class function TAtlasMenuContextRules.Applies(AKnown, AContextual: Boolean; const AWhen: TAtlasMenuWhen;
  const AContext: TAtlasMenuContext): Boolean;
begin
  Result := True;
  if AKnown and AContextual and Assigned(AWhen) then
  begin
    Result := AWhen(AContext);
  end;
end;

class function TAtlasMenuContextRules.CountedCaption(const ACaption: string; ACount: Integer): string;
begin
  Result := ACaption;
  if ACount > 0 then
  begin
    Result := Format('%s (%d)', [ACaption, ACount]);
  end;
end;

class function TAtlasMenuContextRules.Separators(const AIsLine, AVisible: TArray<Boolean>): TArray<Boolean>;
var
  mIndex, mPending: Integer;
  mSeen: Boolean;
begin
  SetLength(Result, Length(AIsLine));
  mPending := -1;
  mSeen := False;
  for mIndex := 0 to High(AIsLine) do
  begin
    Result[mIndex] := False;
    if AIsLine[mIndex] then
    begin
      if mSeen then
      begin
        mPending := mIndex;
      end;
      Continue;
    end;
    Result[mIndex] := (mIndex <= High(AVisible)) and AVisible[mIndex];
    if Result[mIndex] then
    begin
      if mPending >= 0 then
      begin
        Result[mPending] := True;
      end;
      mPending := -1;
      mSeen := True;
    end;
  end;
end;

end.
