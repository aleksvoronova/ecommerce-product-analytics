from pathlib import Path
import pandas as pd


FILE_MAP = {
    "olist_customers_dataset": "olist_customers_dataset.csv",
    "olist_geolocation_dataset": "olist_geolocation_dataset.csv",
    "olist_order_items_dataset": "olist_order_items_dataset.csv",
    "olist_order_payments_dataset": "olist_order_payments_dataset.csv",
    "olist_order_reviews_dataset": "olist_order_reviews_dataset.csv",
    "olist_orders_dataset": "olist_orders_dataset.csv",
    "olist_products_dataset": "olist_products_dataset.csv",
    "olist_sellers_dataset": "olist_sellers_dataset.csv",
    "product_category_name_translation": "product_category_name_translation.csv",
}


def load_raw_data(raw_dir):
    """
    Загружает исходные Olist CSV-файлы из указанной папки.

    Parameters
    ----------
    raw_dir : str | Path
        Путь к папке data/raw.

    Returns
    -------
    dict
        Словарь DataFrame с исходными таблицами.
    """

    raw_dir = Path(raw_dir)

    if not raw_dir.exists():
        raise FileNotFoundError(
            f"Папка с исходными данными не найдена:\n{raw_dir}"
        )

    dataframes = {}

    print("=" * 70)
    print("ЗАГРУЗКА RAW DATA")
    print("=" * 70)

    for dataset_name, file_name in FILE_MAP.items():

        file_path = raw_dir / file_name

        if not file_path.exists():

            # geolocation для проекта не критичен
            if dataset_name == "olist_geolocation_dataset":
                print(
                    f"⚠ {file_name} не найден — geolocation пропущен"
                )
                continue

            raise FileNotFoundError(
                f"Не найден обязательный файл:\n{file_path}"
            )

        df = pd.read_csv(file_path)

        dataframes[dataset_name] = df

        print(
            f"✓ {dataset_name:<35} "
            f"{df.shape[0]:>10,} строк × "
            f"{df.shape[1]:>3} столбцов"
        )

    print("=" * 70)
    print("RAW DATA УСПЕШНО ЗАГРУЖЕНЫ")
    print("=" * 70)

    return dataframes