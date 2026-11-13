unit Atlas.Common.Lsp.AffectedTests.Contract;

// Typen der betroffenen Tests (#1353): geänderte Stelle, übersprungene Datei, Grund, Test, Eingabe, Anfrage und
// Ergebnis. Die Bestimmung (Atlas.Common.Lsp.AffectedTests) und die Ausgabe (Atlas.Common.Lsp.AffectedTests.Report)
// nutzen sie.

interface

uses
  Atlas.Common.Rules.ChangedFiles,
  Atlas.Common.Lsp.Hierarchies,
  Atlas.Common.Lsp.Impact;

const
  /// <summary>Trenner der Schritte eines Wegs.</summary>
  cAffectedArrow = ' → ';

type
{$SCOPEDENUMS ON}
  /// <summary>Was sich geändert hat: ein Symbol oder die Unit als Ganzes (uses, initialization).</summary>
  TAffectedChangeKind = (Symbol, WholeUnit);
  /// <summary>Ausgabe von --affected-tests und get_affected_tests.</summary>
  TAffectedFormat = (Text, Json, DUnitX);
{$SCOPEDENUMS OFF}

  TAffectedChange = record
    Kind: TAffectedChangeKind;
    /// <summary>Das geänderte Symbol; bei WholeUnit Name und UnitName = Unit, FileName = ihre Datei.</summary>
    Item: THierarchyItem;
    /// <summary>Geänderte Datei (bei .dfm und .inc diese, sonst die Unit).</summary>
    Source: string;
    /// <summary>Wo die Änderung liegt: interface, implementation, initialization, Formular, Include.</summary>
    Place: string;
    /// <summary>"TBaseline.Match" bzw. "Unit Atlas.Foo".</summary>
    function Text: string;
  end;

  /// <summary>Geänderte Datei, die keine Tests betrifft, mit Grund.</summary>
  TAffectedSkipped = record
    FileName: string;
    Reason: string;
  end;

  TAffectedReason = record
    /// <summary>Text der geänderten Stelle (TAffectedChange.Text).</summary>
    Change: string;
    /// <summary>Weg von der geänderten Stelle bis zum Test, beide eingeschlossen.</summary>
    Path: TArray<string>;
    /// <summary>Ein Schritt des Wegs ist erschlossen (#1119), nicht sicher.</summary>
    Inferred: Boolean;
    /// <summary>"TBaseline.Match → TFoo.Bar → TFooTests.Test" mit „(erschlossen)“.</summary>
    function Text: string;
  end;

  TAffectedTest = record
    /// <summary>Unit.Fixture.Methode, bei einer ganzen Fixture Unit.Fixture.</summary>
    Name: string;
    /// <summary>Namen für --run bzw. run_tests (bei [TestCase] je Fall).</summary>
    RunNames: TArray<string>;
    UnitName: string;
    Fixture: string;
    /// <summary>'' = die ganze Fixture.</summary>
    Method: string;
    FileName: string;
    /// <summary>0-basiert: Kopf der Testmethode bzw. Deklaration der Fixture.</summary>
    Line: Integer;
    Reasons: TArray<TAffectedReason>;
  end;

  /// <summary>Geänderte Datei mit ihren Zeilen; ohne Zeilen (HasLines = False) gilt sie als ganz geändert.</summary>
  TAffectedInput = record
    FileName: string;
    Lines: TChangedLines;
    HasLines: Boolean;
  end;

  TAffectedRequest = record
    /// <summary>Projektdateien aller Projekte (Referenzsuche).</summary>
    Files: TArray<string>;
    /// <summary>Hauptdateien der Testprogramme (.dpr); ihre Änderung betrifft alle Tests.</summary>
    TestPrograms: TArray<string>;
    /// <summary>Tiefe, Treffersicherheit, Testunits und Zeitlimit je Symbol.</summary>
    Options: TImpactOptions;
    /// <summary>Nur für die Ausgabe: Ref, Revision oder BASE.</summary>
    Base: string;
  end;

  TAffectedResult = record
    Base: string;
    Depth: Integer;
    /// <summary>Alle Tests sind nötig (AllReason sagt warum).</summary>
    All: Boolean;
    AllReason: string;
    Changes: TArray<TAffectedChange>;
    Skipped: TArray<TAffectedSkipped>;
    Tests: TArray<TAffectedTest>;
    Limits: TImpactLimits;
    /// <summary>Alle Namen für --run bzw. run_tests, ohne Doppelte, in Reihenfolge der Tests.</summary>
    function RunNames: TArray<string>;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TAffectedContractText = (Inferred);

const
  cTexts: array[TAffectedContractText] of TAtlasText = (
    (De: ' (erschlossen)'; En: ' (inferred)'));

{$SCOPEDENUMS OFF}

{ TAffectedChange }

function TAffectedChange.Text: string;
begin
  if Kind = TAffectedChangeKind.WholeUnit then
  begin
    Result := 'Unit ' + Item.Name;
  end
  else if Item.Container <> '' then
  begin
    Result := Item.Container + '.' + Item.Name;
  end
  else
  begin
    Result := Item.Name;
  end;
end;

{ TAffectedReason }

function TAffectedReason.Text: string;
begin
  Result := string.Join(cAffectedArrow, Path);
  if Result = '' then
  begin
    Result := Change;
  end;
  if Inferred then
  begin
    Result := Result + cTexts[TAffectedContractText.Inferred].Text;
  end;
end;

{ TAffectedResult }

function TAffectedResult.RunNames: TArray<string>;
var
  mTest: TAffectedTest;
  mName: string;
  mSeen: TDictionary<string, Boolean>;
begin
  Result := nil;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    for mTest in Tests do
    begin
      for mName in mTest.RunNames do
      begin
        if not mSeen.ContainsKey(UpperCase(mName)) then
        begin
          mSeen.Add(UpperCase(mName), True);
          Result := Result + [mName];
        end;
      end;
    end;
  finally
    mSeen.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.AffectedTests.Contract', cTexts);

end.
