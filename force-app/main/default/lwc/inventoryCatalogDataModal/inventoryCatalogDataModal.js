import { api, LightningElement, wire } from "lwc";
import { CloseActionScreenEvent } from "lightning/actions";
import { CurrentPageReference } from "lightning/navigation";
import { RefreshEvent } from "lightning/refresh";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { notifyRecordUpdateAvailable } from "lightning/uiRecordApi";
import getCatalogData from "@salesforce/apex/InventoryCatalogDataController.getCatalogData";

export default class InventoryCatalogDataModal extends LightningElement {
    _recordId;
    pageReference;

    hasStarted = false;
    recordIdTimer;

    connectedCallback() {
        this.recordIdTimer = window.setTimeout(() => {
            if (!this.hasStarted) {
                this.hasStarted = true;
                this.completeAction(
                    "Catalog update failed",
                    "The Inventory record ID could not be determined. Close the window and try again.",
                    "error",
                    []
                );
            }
        }, 3000);
    }

    disconnectedCallback() {
        window.clearTimeout(this.recordIdTimer);
    }

    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        this._recordId = value;
        this.startRequestWhenReady();
    }

    @wire(CurrentPageReference)
    setCurrentPageReference(pageReference) {
        this.pageReference = pageReference;
        this.startRequestWhenReady();
    }

    renderedCallback() {
        this.startRequestWhenReady();
    }

    startRequestWhenReady() {
        const currentRecordId =
            this._recordId ||
            this.pageReference?.state?.recordId ||
            this.pageReference?.attributes?.recordId;

        if (this.hasStarted || !currentRecordId) {
            return;
        }

        this.hasStarted = true;
        window.clearTimeout(this.recordIdTimer);
        void this.loadCatalogData(currentRecordId);
    }

    async loadCatalogData(currentRecordId) {
        try {
            const responseBody = await getCatalogData({ recordId: currentRecordId });
            const response = JSON.parse(responseBody);
            const product = response?.order?.[0] || response?.products?.[0];
            const applyErrors = response?._salesforceApplyResult?.errors || [];
            const recordIdsToRefresh = [
                ...new Set(
                    [currentRecordId, response?._salesforceInventoryRecordId].filter(Boolean)
                )
            ];

            if (applyErrors.length > 0) {
                await this.completeAction(
                    "Catalog update completed with errors",
                    "Catalog data was retrieved, but some data could not be saved in Salesforce.",
                    "error",
                    recordIdsToRefresh
                );
            } else if (product?.found === true) {
                await this.completeAction(
                    "Catalog data updated",
                    "Catalog data was retrieved and saved successfully.",
                    "success",
                    recordIdsToRefresh
                );
            } else if (product?.found === false) {
                await this.completeAction(
                    "Product not found",
                    "The product was not found in the current catalog.",
                    "info",
                    recordIdsToRefresh
                );
            } else {
                await this.completeAction(
                    "Catalog update failed",
                    "The catalog returned an unexpected response.",
                    "error",
                    []
                );
            }
        } catch (error) {
            await this.completeAction(
                "Catalog update failed",
                error?.body?.message || error?.message || "An unexpected error occurred.",
                "error",
                []
            );
        }
    }

    async completeAction(title, message, variant, recordIdsToRefresh) {
        if (recordIdsToRefresh.length > 0) {
            try {
                await notifyRecordUpdateAvailable(
                    recordIdsToRefresh.map((recordId) => ({ recordId }))
                );
            } catch {
                // RefreshView below remains available if an LDS record is not cached.
            }
            this.dispatchEvent(new RefreshEvent());
        }

        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );

        this.dispatchEvent(new CloseActionScreenEvent());
    }
}
