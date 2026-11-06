unit Atlas.Common.Editing.Inlining.Types;

// Typen für „Einbetten“ (#103, Teil A): Dateien, Optionen, Namensauflösung
// und der Aufruf an der Einfügemarke. Die Logik steht in
// Atlas.Common.Editing.Inlining (Variable einbetten, Einstieg),
// Atlas.Common.Editing.Inlining.Method (Methode einbetten) und
// Atlas.Common.Editing.Inlining.Syntax (gemeinsame Hilfen).

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree;

const
  /// <summary>Art der Einbetten-Aktionen (LSP).</summary>
  cInlineKind = 'refactor.inline';
  /// <summary>Endung der Variablen, die das Ergebnis einer eingebetteten Funktion trägt.</summary>
  cInlineResultSuffix = 'Result';

type
{$SCOPEDENUMS ON}
  TInlineVisibility = (Public, Protected, StrictProtected, Private, StrictPrivate);
{$SCOPEDENUMS OFF}

  /// <summary>Bedeutung eines Namens laut Namensauflösung.</summary>
  TInlineMeaning = record
    Found: Boolean;
    /// <summary>Kennung der Deklaration: gleich, wenn zwei Stellen dasselbe meinen.</summary>
    Key: string;
    /// <summary>Feld, Methode oder Eigenschaft eines Typs.</summary>
    IsMember: Boolean;
    /// <summary>Routine oder Methode: Ein Zugriff ruft auf.</summary>
    IsRoutine: Boolean;
    /// <summary>Typ: Ein Aufruf ist eine Typumwandlung.</summary>
    IsType: Boolean;
    /// <summary>Typ des Mitglieds; '' sonst.</summary>
    Container: string;
    Visibility: TInlineVisibility;
  end;

  /// <summary>Bedeutung der Kette ANames (A.B.C), wie sie in ATree (Datei AFileName) an AOffset stünde.</summary>
  TInlineLookup = reference to function(ATree: TSyntaxTree; const AFileName: string;
    const ANames: TArray<string>; AOffset: Integer): TInlineMeaning;

  /// <summary>Eine Datei mit Text und Syntaxbaum.</summary>
  TInlineSource = record
    FileName: string;
    Text: string;
    Tree: TSyntaxTree;
    class function Create(const AFileName, AText: string; ATree: TSyntaxTree): TInlineSource; static;
  end;

  /// <summary>Die Methode, die eingebettet wird: Rumpf ARoutine in der Datei ASource.</summary>
  TInlineCallee = record
    Source: TInlineSource;
    Routine: TSyntaxNode;
    class function Create(const ASource: TInlineSource; ARoutine: TSyntaxNode): TInlineCallee; static;
  end;

  TInlineOptions = record
    /// <summary>Inline-Variablen erzeugen (Einstellung und Sprachversion).</summary>
    InlineVar: Boolean;
    Style: TFormatStyle;
    /// <summary>Namensauflösung; nil: alle fremden Namen gelten als gleich und nicht als Mitglieder.</summary>
    Lookup: TInlineLookup;
    class function Default: TInlineOptions; static;
  end;

  /// <summary>Aufruf an der Einfügemarke.</summary>
  TInlineCall = record
    /// <summary>Kurzer Name der aufgerufenen Routine.</summary>
    Name: string;
    NameOffset: Integer;
    NamePos: TTextPosition;
    /// <summary>Identifier bzw. MemberAccess mit dem Namen.</summary>
    Callee: TSyntaxNode;
    /// <summary>Ausdruck, den der Rumpf ersetzt: Call oder der Name selbst (ohne Klammern).</summary>
    Node: TSyntaxNode;
    /// <summary>Qualifizierer vor dem Namen; nil ohne.</summary>
    Receiver: TSyntaxNode;
    Arguments: TArray<TSyntaxNode>;
    /// <summary>CallStatement, wenn der Aufruf die ganze Anweisung ist; nil im Ausdruck.</summary>
    Statement: TSyntaxNode;
  end;

implementation

{ TInlineSource }

class function TInlineSource.Create(const AFileName, AText: string; ATree: TSyntaxTree): TInlineSource;
begin
  Result.FileName := AFileName;
  Result.Text := AText;
  Result.Tree := ATree;
end;

{ TInlineCallee }

class function TInlineCallee.Create(const ASource: TInlineSource; ARoutine: TSyntaxNode): TInlineCallee;
begin
  Result.Source := ASource;
  Result.Routine := ARoutine;
end;

{ TInlineOptions }

class function TInlineOptions.Default: TInlineOptions;
begin
  Result.InlineVar := True;
  Result.Style := TFormatStyle.Default;
  Result.Lookup := nil;
end;

end.
