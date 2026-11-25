unit Atlas.Common.CodeActions.Contract.Classes;

// Werte der Klassen-Aktionen (Methode überschreiben, Interface implementieren, Feld oder Zugriffsmethode
// anlegen), die Prüfregeln als Korrektur anbieten und Editing erzeugt. Beide Seiten tauschen nur diese Werte und
// TCodeAction aus; keine muss die andere einbinden.

interface

uses
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract;

type
  {$SCOPEDENUMS ON}
  /// <summary>Art des fehlenden Mitglieds einer Eigenschaft (#467, #1001).</summary>
  TAccessorKind = (Field, Getter, Setter);
  {$SCOPEDENUMS OFF}

  /// <summary>Fehlendes Feld bzw. fehlende Zugriffsmethode einer Eigenschaft.</summary>
  TAccessorPlan = record
    Kind: TAccessorKind;
    /// <summary>Name der Eigenschaft (Caption).</summary>
    PropertyName: string;
    PropertyType: string;
    /// <summary>Indexparameter ohne Klammern ("Index: Integer"); '' ohne.</summary>
    IndexParameters: string;
    /// <summary>Abschnitt der Methoden: private oder protected.</summary>
    MethodSection: string;
    /// <summary>Name des neuen Mitglieds: FCaption, GetCaption, SetCaption.</summary>
    function Name: string;
    function FieldName: string;
  end;

  /// <summary>Wo und womit eine Klassen-Aktion rechnet: Quelltext, Zeile in der Klassendeklaration, Index für
  /// Vorfahren und Interfaces aus anderen Units, Formatstil.</summary>
  TClassEditRequest = record
    Text: string;
    /// <summary>Zeile (ab 0) in der Deklaration der Klasse bzw. der Eigenschaft.</summary>
    Line: Integer;
    Index: ISymbolIndex;
    Namespaces: TArray<string>;
    DelphiVersion: string;
    Style: TFormatStyle;
    class function Create(const AText: string; ALine: Integer): TClassEditRequest; static;
    /// <summary>Dieselbe Anfrage für Zeile ALine.</summary>
    function At(ALine: Integer): TClassEditRequest;
  end;

implementation

{ TAccessorPlan }

function TAccessorPlan.Name: string;
begin
  case Kind of
    TAccessorKind.Getter:
      Result := 'Get' + PropertyName;
    TAccessorKind.Setter:
      Result := 'Set' + PropertyName;
  else
    Result := FieldName;
  end;
end;

function TAccessorPlan.FieldName: string;
begin
  Result := 'F' + PropertyName;
end;

{ TClassEditRequest }

class function TClassEditRequest.Create(const AText: string; ALine: Integer): TClassEditRequest;
begin
  Result := Default(TClassEditRequest);
  Result.Text := AText;
  Result.Line := ALine;
  Result.Style := TFormatStyle.Default;
end;

function TClassEditRequest.At(ALine: Integer): TClassEditRequest;
begin
  Result := Self;
  Result.Line := ALine;
end;

end.
