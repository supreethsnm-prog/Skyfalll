from sqlalchemy import Column, DateTime, Float, Integer, String
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import declarative_base

Base = declarative_base()


class Alert(Base):
    __tablename__ = "alerts"

    id = Column(Integer, primary_key=True)
    external_id = Column(String, unique=True, nullable=False, index=True)
    source = Column(String, nullable=False)
    severity = Column(String, nullable=False)
    event_type = Column(String, nullable=False)
    area_description = Column(String, nullable=True)
    effective_start_time = Column(String, nullable=True)
    effective_end_time = Column(String, nullable=True)
    warning_message = Column(String, nullable=True)
    severity_color = Column(String, nullable=True)
    latitude = Column(Float, nullable=True)
    longitude = Column(Float, nullable=True)
    raw_payload = Column(JSONB, nullable=False)
    fetched_at = Column(DateTime(timezone=True), nullable=False)
