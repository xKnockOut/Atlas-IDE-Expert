unit BDLsp.Common.Lsp.InactiveRegions;

// Inaktive Bereiche der bedingten Kompilierung ({$IFDEF} usw.) einer Datei
// für das Abblenden im Editor. Ein Bereich reicht vom Ende der Direktive,
// die den Zweig abschaltet, bis zur nächsten wirksamen Direktive. Bereiche
// aus Include-Dateien gehören nicht zur Datei selbst und entfallen.

interface

uses
  System.SysUtils,
  BDLsp.Common.Documents.Contract;

type
  TLspInactiveRegions = record
  public
    /// <summary>Inaktive Zeilenbereiche in AText für die Symbole ADefines.</summary>
    class function Ranges(const AText: string; const ADefines: TArray<string>): TArray<TTextRange>; static;
  end;

implementation

uses
  BDLsp.Common.Pascal.Preprocessor;

class function TLspInactiveRegions.Ranges(const AText: string; const ADefines: TArray<string>): TArray<TTextRange>;
var
  Options: TPreprocessorOptions;
  Processed: TPreprocessorResult;
  Inactive: TInactiveRange;
  Range: TTextRange;
begin
  Result := nil;
  Options := TPreprocessorOptions.Default;
  Options.Defines := ADefines;
  Processed := TPascalPreprocessor.Process(AText, Options);
  for Inactive in Processed.InactiveRanges do
  begin
    if Inactive.FileIndex <> 0 then
      Continue;
    Range := Inactive.Range;
    // Leere Bereiche ({$IFDEF X}{$ENDIF}) nicht melden.
    if Range.StartPos = Range.EndPos then
      Continue;
    Result := Result + [Range];
  end;
end;

end.
