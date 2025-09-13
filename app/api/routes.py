from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
from typing import List, Dict, Any
import logging
from ..core.auth import require_api_key

logger = logging.getLogger(__name__)
router = APIRouter()

class ItemCreate(BaseModel):
    name: str
    description: str
    price: float

class Item(BaseModel):
    id: int
    name: str
    description: str
    price: float

# In-memory storage for demo purposes
items_db: List[Item] = []

@router.get("/")
async def root():
    return {"message": "Welcome to AWS ECS API Template"}

@router.get("/items", response_model=List[Item])
async def get_items(_: str = Depends(require_api_key)):
    return items_db

@router.get("/items/{item_id}", response_model=Item)
async def get_item(item_id: int, _: str = Depends(require_api_key)):
    for item in items_db:
        if item.id == item_id:
            return item
    raise HTTPException(status_code=404, detail="Item not found")

@router.post("/items", response_model=Item)
async def create_item(item: ItemCreate, _: str = Depends(require_api_key)):
    new_id = len(items_db) + 1
    new_item = Item(id=new_id, **item.dict())
    items_db.append(new_item)
    logger.info(f"Created item with id: {new_id}")
    return new_item

@router.put("/items/{item_id}", response_model=Item)
async def update_item(item_id: int, item_update: ItemCreate, _: str = Depends(require_api_key)):
    for i, item in enumerate(items_db):
        if item.id == item_id:
            updated_item = Item(id=item_id, **item_update.dict())
            items_db[i] = updated_item
            logger.info(f"Updated item with id: {item_id}")
            return updated_item
    raise HTTPException(status_code=404, detail="Item not found")

@router.delete("/items/{item_id}")
async def delete_item(item_id: int, _: str = Depends(require_api_key)):
    for i, item in enumerate(items_db):
        if item.id == item_id:
            deleted_item = items_db.pop(i)
            logger.info(f"Deleted item with id: {item_id}")
            return {"message": f"Item {item_id} deleted successfully"}
    raise HTTPException(status_code=404, detail="Item not found")