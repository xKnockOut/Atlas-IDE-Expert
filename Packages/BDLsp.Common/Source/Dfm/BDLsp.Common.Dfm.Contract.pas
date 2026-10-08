unit BDLsp.Common.Dfm.Contract;

// Contract des Platform-Features Dfm (#44): Baum einer Text-DFM bzw. -FMX.
// Positionen wie im LSP: Zeile und Spalte ab 0, Spalte in UTF-16-Codeeinheiten.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  BDLsp.Common.Documents.Contract;

type
  {$SCOPEDENUMS ON}
  /// <summary>object, inherited, inline oder ein Eintrag einer Collection (item).</summary>
  TDfmObjectKind = (Object_, Inherited_, Inline_, Item);
  {$SCOPEDENUMS OFF}

  TDfmProperty = record
    /// <summary>Name wie in der Datei, auch mit Punkten (Font.Name).</summary>
    Name: string;
    /// <summary>Wert als Quelltext, bei mehrzeiligen Werten mit Zeilenumbrüchen.</summary>
    Value: string;
    NameRange: TTextRange;
    ValueRange: TTextRange;
    /// <summary>Ereignis wie OnClick = Button1Click: Wert ist ein Methodenname.</summary>
    function IsEvent: Boolean;
  end;

  TDfmObject = class
  private
    FChildren: TObjectList<TDfmObject>;
  public
    Kind: TDfmObjectKind;
    /// <summary>Komponentenname; '' bei "object TFoo" ohne Namen und bei Collection-Einträgen.</summary>
    Name: string;
    /// <summary>Klassenname wie TButton; '' bei Collection-Einträgen.</summary>
    TypeName: string;
    NameRange: TTextRange;
    TypeRange: TTextRange;
    /// <summary>Vom Schlüsselwort bis zum zugehörigen end.</summary>
    Range: TTextRange;
    Properties: TArray<TDfmProperty>;
    constructor Create;
    destructor Destroy; override;
    property Children: TObjectList<TDfmObject> read FChildren;
  end;

  TDfmError = record
    Position: TTextPosition;
    Message: string;
  end;

  TDfmDocument = class
  private
    FRoot: TDfmObject;
  public
    Errors: TArray<TDfmError>;
    destructor Destroy; override;
    /// <summary>Wurzelobjekt (das Formular); nil, wenn die Datei keines enthält.</summary>
    property Root: TDfmObject read FRoot write FRoot;
  end;

implementation

{ TDfmProperty }

function TDfmProperty.IsEvent: Boolean;
var
  Index: Integer;
begin
  // OnXyz mit einem Bezeichner als Wert.
  Result := (Length(Name) > 2) and SameText(Copy(Name, 1, 2), 'On') and CharInSet(Name[3], ['A'..'Z']) and
    (Value <> '') and CharInSet(Value[1], ['A'..'Z', 'a'..'z', '_']);
  if Result then
    for Index := 2 to Length(Value) do
      if not CharInSet(Value[Index], ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
        Exit(False);
end;

{ TDfmObject }

constructor TDfmObject.Create;
begin
  inherited Create;
  FChildren := TObjectList<TDfmObject>.Create(True);
end;

destructor TDfmObject.Destroy;
begin
  FChildren.Free;
  inherited;
end;

{ TDfmDocument }

destructor TDfmDocument.Destroy;
begin
  FRoot.Free;
  inherited;
end;

end.
