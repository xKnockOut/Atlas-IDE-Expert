unit Atlas.Common.Semantics.Contract;

// Contract des Features Semantics: Auswertungen, die mehrere Namensauflöser
// teilen.
//
// - ITreeUnits hält den Unit-Index eines Syntaxbaums für alle Resolver eines
//   Prüflaufs (#1322). Ohne sie wertete jede Typabfrage (NodeType, Resolve)
//   eines nicht gepinnten Resolvers die ganze Unit neu aus, und Regeln mit
//   vielen Abfragen wurden quadratisch in der Unitgröße.
// - TUsesUnitInfo, TUsesResolution und ihre Funktionstypen beschreiben die
//   Nutzung der uses-Einträge aus der Namensauflösung (#1925, TUsesUsage),
//   die die uses-Aktionen von Editing auswerten.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  // Genehmigte Ausnahme der Rollenmatrix (Architektur.md, "Genehmigte Ausnahmen"): wie in Rules.Contract ist
  // der Syntaxbaum die Datengrundlage und hängt selbst nur an Contracts.
  Atlas.Common.Pascal.SyntaxTree;

type
  /// <summary>Was der Index über eine Unit weiß.</summary>
  TUsesUnitInfo = record
    Known: Boolean;
    HasInitialization: Boolean;
    /// <summary>Namen der interface-Symbole, auch Mitglieder.</summary>
    Names: TArray<string>;
    /// <summary>Namen der interface-Symbole auf Unit-Ebene samt Enum-Werten (#1925): nur sie braucht ein
    /// Bezeichner, der nicht hinter einem Punkt steht, aus dem uses.</summary>
    TopNames: TArray<string>;
    /// <summary>Namen der Mitglieder von Class- und Record-Helpern im interface (#1925): Hinter einem Punkt
    /// braucht nur ein Helper seine Unit im uses.</summary>
    HelperNames: TArray<string>;
    /// <summary>Die Formulardatei der geprüften Unit verweist auf ein Modul dieser Unit (Connection =
    /// Form1.Connection): Der Eintrag gilt als im implementation-Teil verwendet, die IDE braucht ihn
    /// (dfm-reference-unit-missing).</summary>
    UsedByForm: Boolean;
  end;

  TUsesUnitInfoFunc = reference to function(const AUnitName: string): TUsesUnitInfo;

  /// <summary>Units, deren interface ein Symbol AName auf Unit-Ebene deklariert.</summary>
  TUnitsDeclaringFunc = reference to function(const AName: string): TArray<string>;

  /// <summary>Nutzung der uses-Einträge aus der Namensauflösung (#1925, TUsesUsage). Bezeichner, deren
  /// Deklaration feststeht, zählen nur für die Unit dieser Deklaration; die übrigen vergleicht TUsesActions mit den
  /// Namen der Units wie zuvor, aber genauer: vor einem Punkt mit TopNames, dahinter mit HelperNames. Ohne Active
  /// gilt der großzügige Namensvergleich mit allen Namen.</summary>
  TUsesResolution = record
  public const
    cInterfacePart = 1;
    cImplementationPart = 2;
  public
    Active: Boolean;
    /// <summary>Offsets der Bezeichner mit bekannter Deklaration, aufsteigend.</summary>
    Settled: TArray<Integer>;
    /// <summary>uses-Einträge, wie sie dastehen, und je Eintrag die Teile (cInterfacePart, cImplementationPart),
    /// in denen ihn ein aufgelöster Bezeichner oder ein Rumpf einer gerufenen inline-Routine braucht.</summary>
    Units: TArray<string>;
    Masks: TArray<Integer>;
    function IsSettled(AOffset: Integer): Boolean;
    function MaskOf(const AName: string): Integer;
  end;

  /// <summary>Nutzung der uses-Einträge von AText (Token in AInactive zählen nicht); nicht Active, wenn sich der
  /// Text nicht auflösen lässt (Syntaxfehler, kein Index).</summary>
  TUsesResolveFunc = reference to function(const AText: string; const AInactive: TArray<TTextRange>): TUsesResolution;

  /// <summary>Wie TUsesResolveFunc für einen schon übersetzten Baum (ohne zweites Parsen, etwa für /sortuses in
  /// großen Units); der Baum bleibt beim Aufrufer.</summary>
  TUsesTreeResolveFunc = reference to function(ATree: TSyntaxTree;
    const AInactive: TArray<TTextRange>): TUsesResolution;

  /// <summary>Unit-Index genau eines Syntaxbaums, einmal ausgewertet und von allen Resolvern eines Laufs
  /// geteilt (#1322). Gilt nur in einem Thread und nur, solange der Baum lebt: Der Besitzer ruft Clear,
  /// bevor er den Baum freigibt.</summary>
  ITreeUnits = interface
    ['{64C9DAD4-B538-4A12-93ED-55334C477C28}']
    /// <summary>Gehört die Auswertung zu ATree? Nur dann liefern Extracted und Merged dessen Stand.</summary>
    function Holds(ATree: TSyntaxTree): Boolean;
    /// <summary>Wie TIndexExtractor.Extract(Baum, AFileName), je Dateiname einmal ausgewertet.</summary>
    function Extracted(const AFileName: string): TUnitIndex;
    /// <summary>Extracted samt der Symbole der Include-Dateien aus AIndex und mit Namenstabelle, wie
    /// TNameResolver sie für Prepare braucht; je Dateiname einmal, solange AIndex derselbe bleibt.</summary>
    function Merged(const AIndex: ISymbolIndex; const AFileName: string): TUnitIndex;
    /// <summary>Vergisst Baum und Auswertungen; danach gehört sie zu keinem Baum mehr.</summary>
    procedure Clear;
  end;

implementation

uses
  System.StrUtils;

{ TUsesResolution }

function TUsesResolution.IsSettled(AOffset: Integer): Boolean;
var
  mLow, mHigh, mMiddle: Integer;
begin
  mLow := 0;
  mHigh := High(Settled);
  while mLow <= mHigh do
  begin
    mMiddle := (mLow + mHigh) div 2;
    if Settled[mMiddle] = AOffset then
    begin
      Exit(True);
    end;
    if Settled[mMiddle] < AOffset then
    begin
      mLow := mMiddle + 1;
    end
    else
    begin
      mHigh := mMiddle - 1;
    end;
  end;
  Result := False;
end;

function TUsesResolution.MaskOf(const AName: string): Integer;
var
  mIndex: Integer;
begin
  mIndex := IndexText(AName, Units);
  if mIndex < 0 then
  begin
    Exit(0);
  end;
  Result := Masks[mIndex];
end;

end.
