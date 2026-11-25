unit Atlas.Common.Editing.Contract.MethodWithoutSelf;

// Methoden, die Self nicht brauchen (#686), samt Umwandlung in eine class-Methode, die Editing anderen Features
// anbietet (API). Abnehmer ist die Prüfregel method-without-self über den Host-Adapter Adapters.Rules.Refactorings;
// erzeugt in Atlas.Common.Editing.Composition.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.CodeActions.Contract;

type
  /// <summary>Was die Suche über eine Unit wissen muss.</summary>
  TEditingMethodScan = record
    /// <summary>Dateiname für die Namensauflösung.</summary>
    FileName: string;
    Text: string;
    /// <summary>Baum zu Text, gehört dem Aufrufer.</summary>
    Tree: IPascalSyntaxTree;
    /// <summary>Inhalt der Formulardatei; '' ohne. Ereignisse des Formulars brauchen eine Methode des Objekts.
    /// </summary>
    FormText: string;
    Index: ISymbolIndex;
    EnsureUnit: TEnsureUnitFunc;
    Namespaces: TArray<string>;
    /// <summary>class-Methoden mit static (refactoring.methodKind).</summary>
    WithStatic: Boolean;
    Style: TFormatStyle;
  end;

  /// <summary>Eine Methode ohne Self.</summary>
  TEditingMethodWithoutSelf = record
    ClassName: string;
    Name: string;
    /// <summary>Name im Kopf der Implementierung.</summary>
    NamePosition: TTextPosition;
    /// <summary>Umwandlung in eine class-Methode, nur Änderungen dieser Unit; ohne HasFix nicht möglich.</summary>
    HasFix: Boolean;
    Fix: TCodeAction;
  end;

  IEditingMethodsWithoutSelf = interface
    ['{33BF8D9C-AF8E-4735-A13B-728EE41AB3C9}']
    /// <summary>Alle Methoden der Unit, die Self nicht brauchen; leer ohne Baum.</summary>
    function Scan(const AScan: TEditingMethodScan): TArray<TEditingMethodWithoutSelf>;
  end;

implementation

end.
