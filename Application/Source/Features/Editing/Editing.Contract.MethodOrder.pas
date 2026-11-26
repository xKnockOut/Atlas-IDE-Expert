unit Editing.Contract.MethodOrder;

// Prüfung der Methodenordnung je Typ (#1840), die Editing anderen Features anbietet (API). Abnehmer ist die
// Prüfregel method-order über den Host-Adapter Adapters.Checks.Refactorings; erzeugt in
// Editing.Composition.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract;

type
  /// <summary>Wie die Rümpfe geordnet sein sollen.</summary>
  TEditingMethodOrderRequest = record
    /// <summary>off, declaration, alphabetical, grouped; '' = grouped, Unbekanntes = declaration.</summary>
    Placement: string;
    /// <summary>Lebenszyklus auch bei declaration und alphabetical zuerst.</summary>
    LifecycleFirst: Boolean;
    /// <summary>Leerzeilen an den Grenzen verschobener Rümpfe angleichen.</summary>
    BlankLines: Boolean;
    /// <summary>Form des Typkommentars wie classCompletion.typeComment; off = keinen verlangen, leer = brace.
    /// </summary>
    TypeComment: string;
    /// <summary>Breite der Trennlinie; 0 = Vorgabe.</summary>
    LineLength: Integer;
  end;

  /// <summary>Stand eines Typs.</summary>
  TEditingMethodTypeReview = record
    TypeName: string;
    /// <summary>Typname im Kopf des ersten Rumpfs.</summary>
    NameRange: TTextRange;
    /// <summary>Ordnet nur die Rümpfe dieses Typs; nil = sie stehen schon in der Ordnung.</summary>
    OrderEdits: TArray<TTextEdit>;
    /// <summary>Fügt den fehlenden Typkommentar ein; nil = vorhanden oder nicht verlangt.</summary>
    CommentEdits: TArray<TTextEdit>;
    /// <summary>Zeile des einzufügenden Kommentars, z. B. "{ TKunde }"; '' ohne.</summary>
    CommentText: string;
  end;

  /// <summary>Ergebnis der Prüfung einer Unit.</summary>
  TEditingMethodOrderReview = record
    /// <summary>Die verstandene Ordnung: off, declaration, alphabetical oder grouped.</summary>
    Placement: string;
    /// <summary>Je Typ mit Rümpfen in der Reihenfolge des ersten Rumpfs; leer bei off.</summary>
    Types: TArray<TEditingMethodTypeReview>;
  end;

  /// <summary>Prüft, ob die Rümpfe je Typ in der Ordnung stehen und ein Typkommentar fehlt.</summary>
  IEditingMethodOrderReview = interface
    ['{E26EBBEF-8463-4AAC-B32A-842E25D93AC1}']
    /// <summary>ATree ist der Baum zu AText; ohne ihn ein leeres Ergebnis.</summary>
    function Review(const AText: string; const ATree: IPascalSyntaxTree;
      const ARequest: TEditingMethodOrderRequest): TEditingMethodOrderReview;
  end;

implementation

end.
